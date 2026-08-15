import type { APIGatewayProxyHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import { GetCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

/**
 * The atomic replacement for what used to be a client-side-only check
 * (`guard balance(for: uid) >= reward.pointCost` in RewardStore.redeem).
 *
 * That check read a locally-cached balance and then wrote unconditionally,
 * so two redemptions racing -- or one client with stale listener state --
 * could both pass and overdraw. Here the balance decrement carries its own
 * ConditionExpression, so the write itself is what enforces sufficiency:
 * either the whole transaction commits or nothing does.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);
    const householdId = await callerHouseholdId(uid);
    const { rewardId, redeemedByUID, redeemedByName } = JSON.parse(event.body ?? '{}');
    if (!rewardId || !redeemedByUID) {
      throw new HttpError(400, 'rewardId and redeemedByUID are required');
    }

    // Cost comes from the stored reward, never from the request body -- a
    // client-supplied price would let anyone redeem anything for 0 points.
    const rewardResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: Keys.reward(householdId, rewardId) })
    );
    const reward = rewardResult.Item;
    if (!reward) {
      throw new HttpError(404, 'That reward no longer exists.');
    }
    const pointsSpent: number = reward.pointCost;

    const id = randomUUID();
    const redeemedAt = new Date().toISOString();
    const redemption = {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `REDEMPTION#${redeemedAt}#${id}`,
      id,
      rewardId,
      rewardName: reward.name,
      pointsSpent,
      redeemedByUID,
      redeemedByName,
      redeemedAt,
      // Redeeming spends the points but doesn't deliver the reward -- a
      // parent hands that over later and marks it fulfilled. Debiting here
      // rather than at fulfillment is deliberate: it keeps the conditional
      // decrement below as the single thing that decides affordability, and
      // stops a member queueing up more requests than they can pay for.
      status: 'pending' as const,
    };

    try {
      await ddb.send(
        new TransactWriteCommand({
          TransactItems: [
            {
              Update: {
                TableName: TABLE_NAME,
                Key: Keys.balance(householdId, redeemedByUID),
                UpdateExpression: 'ADD #balance :negCost',
                // Fails the whole transaction if the balance doesn't cover
                // the cost (or doesn't exist yet, i.e. nothing earned).
                ConditionExpression: 'attribute_exists(#balance) AND #balance >= :cost',
                ExpressionAttributeNames: { '#balance': 'balance' },
                ExpressionAttributeValues: { ':negCost': -pointsSpent, ':cost': pointsSpent },
              },
            },
            { Put: { TableName: TABLE_NAME, Item: redemption } },
          ],
        })
      );
    } catch (error) {
      if (error instanceof Error && error.name === 'TransactionCanceledException') {
        throw new HttpError(409, "That's more points than you have saved up.");
      }
      throw error;
    }

    const { PK, SK, ...body } = redemption;
    return json(201, { redemption: body });
  } catch (error) {
    return errorResponse(error);
  }
};
