import type { APIGatewayProxyHandler } from 'aws-lambda';
import { UpdateCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, requireParent, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';
import {
  findRedemptionById,
  presentRedemption,
  REDEMPTION_STATUSES,
  DEFAULT_STATUS,
  type RedemptionStatus,
} from './redemptions';

/**
 * Moves a redemption through its fulfillment lifecycle.
 *
 * Redeeming a reward spends the points, but the reward itself is handed over
 * by a parent in the real world, later -- so a redemption stays `pending`
 * until a parent says otherwise. Exactly three transitions exist:
 *
 *   pending   -> fulfilled   the reward was handed over
 *   fulfilled -> pending     that was a mistake, put it back in the queue
 *   pending   -> cancelled   called off; the points are returned
 *
 * Each target state has exactly one legal origin, which is why the request
 * carries a target rather than a verb: the target *is* the transition. It
 * also makes `cancelled` terminal for free -- no transition names it as an
 * origin, so nothing can leave it.
 *
 * `fulfilled -> cancelled` is deliberately absent. A parent who marked
 * something fulfilled by mistake un-fulfills it first, which keeps
 * `pending -> cancelled` as the only path that returns points, guarded by a
 * single condition.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);
    const householdId = await callerHouseholdId(uid);

    // Interface-level gating is a convenience; this is the guarantee. A
    // child's token cannot resolve a redemption, including their own.
    const parent = await requireParent(
      householdId,
      uid,
      'Only parents can update a redemption.'
    );

    const redemptionId = event.pathParameters?.redemptionId;
    if (!redemptionId) {
      throw new HttpError(400, 'redemptionId is required');
    }

    const { status: target } = JSON.parse(event.body ?? '{}');
    if (!REDEMPTION_STATUSES.includes(target)) {
      throw new HttpError(400, `status must be one of ${REDEMPTION_STATUSES.join(', ')}`);
    }

    // Scoped to the caller's own household, so a redemption belonging to
    // anyone else is simply not found -- which discloses nothing about
    // whether it exists.
    const redemption = await findRedemptionById(householdId, redemptionId);
    if (!redemption) {
      throw new HttpError(404, 'That redemption no longer exists.');
    }
    const Key = { PK: redemption.PK, SK: redemption.SK };

    let updated: Record<string, any> | undefined;

    try {
      // Every branch below states the origin it requires as a condition on
      // the write itself. The read above only located the item: if a
      // concurrent request resolved it in between, the condition fails
      // rather than one transition silently overwriting the other. That
      // matters most for cancellation, where two winners would refund twice.
      switch (target as RedemptionStatus) {
        case 'fulfilled': {
          const result = await ddb.send(
            new UpdateCommand({
              TableName: TABLE_NAME,
              Key,
              UpdateExpression:
                'SET #status = :fulfilled, fulfilledAt = :now, fulfilledByUID = :uid, fulfilledByName = :name',
              ConditionExpression: '#status = :pending',
              ExpressionAttributeNames: { '#status': 'status' },
              ExpressionAttributeValues: {
                ':fulfilled': 'fulfilled',
                ':pending': 'pending',
                ':now': new Date().toISOString(),
                ':uid': uid,
                ':name': parent.name,
              },
              // Takes the post-write item straight from the write, rather
              // than reading it back -- a Query afterwards is eventually
              // consistent and can hand back the pre-write item.
              ReturnValues: 'ALL_NEW',
            })
          );
          updated = result.Attributes;
          break;
        }

        case 'pending': {
          const result = await ddb.send(
            new UpdateCommand({
              TableName: TABLE_NAME,
              Key,
              UpdateExpression:
                'SET #status = :pending REMOVE fulfilledAt, fulfilledByUID, fulfilledByName',
              // The one place a status-less legacy row is visible to a write.
              // Those rows mean "fulfilled" (see DEFAULT_STATUS), so
              // un-fulfilling one is legal. Nothing else can meet a
              // status-less row: the other two branches require `pending`,
              // which it can never satisfy.
              ConditionExpression: 'attribute_not_exists(#status) OR #status = :fulfilled',
              ExpressionAttributeNames: { '#status': 'status' },
              ExpressionAttributeValues: { ':pending': 'pending', ':fulfilled': 'fulfilled' },
              ReturnValues: 'ALL_NEW',
            })
          );
          updated = result.Attributes;
          break;
        }

        case 'cancelled': {
          await ddb.send(
            new TransactWriteCommand({
              TransactItems: [
                {
                  Update: {
                    TableName: TABLE_NAME,
                    Key,
                    UpdateExpression:
                      'SET #status = :cancelled, cancelledAt = :now, cancelledByUID = :uid',
                    ConditionExpression: '#status = :pending',
                    ExpressionAttributeNames: { '#status': 'status' },
                    ExpressionAttributeValues: {
                      ':cancelled': 'cancelled',
                      ':pending': 'pending',
                      ':now': new Date().toISOString(),
                      ':uid': uid,
                    },
                  },
                },
                {
                  // The mirror image of redeem-reward.ts, and in the same
                  // transaction as the state change for the same reason: a
                  // balance that can disagree with its ledger is the bug
                  // this whole shape exists to prevent.
                  //
                  // The amount comes from what the redemption recorded
                  // spending, not from the reward -- which may have been
                  // repriced or deleted since -- and never from the caller.
                  Update: {
                    TableName: TABLE_NAME,
                    Key: Keys.balance(householdId, redemption.redeemedByUID),
                    UpdateExpression: 'ADD #balance :points',
                    ExpressionAttributeNames: { '#balance': 'balance' },
                    ExpressionAttributeValues: { ':points': Number(redemption.pointsSpent) },
                  },
                },
              ],
            })
          );
          // TransactWriteItems can't return the items it wrote, so this one
          // has to read back -- consistently, for the reason above.
          updated = await findRedemptionById(householdId, redemptionId, { consistent: true });
          break;
        }
      }
    } catch (error) {
      if (
        error instanceof Error &&
        (error.name === 'ConditionalCheckFailedException' ||
          error.name === 'TransactionCanceledException')
      ) {
        throw await conflict(householdId, redemptionId, target);
      }
      throw error;
    }

    return json(200, { redemption: updated ? presentRedemption(updated) : null });
  } catch (error) {
    return errorResponse(error);
  }
};

/**
 * Turns a failed condition into a 409 that names where the redemption
 * actually is now, re-reading it rather than reporting the state we saw
 * before the write -- the whole reason the condition failed is that the
 * earlier read is no longer true.
 */
async function conflict(
  householdId: string,
  redemptionId: string,
  target: RedemptionStatus
): Promise<HttpError> {
  const current = await findRedemptionById(householdId, redemptionId, { consistent: true });
  if (!current) {
    return new HttpError(404, 'That redemption no longer exists.');
  }
  const status: RedemptionStatus = current.status ?? DEFAULT_STATUS;

  if (status === 'cancelled') {
    return new HttpError(409, 'That request was already cancelled.');
  }
  if (status === 'fulfilled' && target === 'cancelled') {
    return new HttpError(
      409,
      'That reward was already handed over. Mark it unfulfilled first if you need to cancel it.'
    );
  }
  if (status === 'fulfilled') {
    return new HttpError(409, 'That request was already fulfilled.');
  }
  return new HttpError(409, 'That request is still waiting to be fulfilled.');
}
