import type { APIGatewayProxyHandler } from 'aws-lambda';
import { GetCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

function resolveNote(rawNote: unknown): string | undefined {
  if (rawNote === undefined) return undefined;
  if (typeof rawNote !== 'string') {
    throw new HttpError(400, 'note must be a string');
  }
  const trimmed = rawNote.trim();
  if (trimmed.length > 500) {
    throw new HttpError(400, 'note must be 500 characters or fewer');
  }
  return trimmed.length > 0 ? trimmed : undefined;
}

/**
 * Unchecks one item on a checklist chore for a given day. Any household
 * member may do this, including the assignee themselves -- fat-fingering a
 * checklist item shouldn't require a parent to fix, the same reasoning
 * that already lets any member complete a chore on anyone's behalf.
 *
 * If the chore hadn't completed yet today, this is just a plain edit to
 * progress. If it had, this is a reversal: the completion is marked
 * reversed (never deleted -- see the append-only ledger requirement), the
 * points are debited back in full, uncapped, and the chore becomes
 * completable again once every item is checked again.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);
    const householdId = await callerHouseholdId(uid);
    const choreId = event.pathParameters?.choreId;
    const itemId = event.pathParameters?.itemId;
    const scheduledDate = event.queryStringParameters?.scheduledDate;
    if (!choreId || !itemId || !scheduledDate) {
      throw new HttpError(400, 'choreId, itemId and scheduledDate are required');
    }

    // Validated before any writes: an over-cap note refuses the whole
    // request, the same contract update-redemption-status.ts uses.
    const note = resolveNote(JSON.parse(event.body ?? '{}').note);

    // Unconditional: removing an item can never complete a checklist, so
    // there's nothing to race here.
    await ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: Keys.checklistProgress(householdId, choreId, scheduledDate),
        UpdateExpression:
          'DELETE checkedItemIds :item SET choreId = :choreId, scheduledDate = :scheduledDate',
        ExpressionAttributeValues: {
          ':item': new Set([itemId]),
          ':choreId': choreId,
          ':scheduledDate': scheduledDate,
        },
      })
    );

    const markerResult = await ddb.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: Keys.completionMarker(householdId, choreId, scheduledDate),
      })
    );
    const marker = markerResult.Item;
    if (!marker) {
      // Pre-completion uncheck -- nothing further to do.
      return json(200, { reversed: false });
    }

    // completedAt + completionId (both on the marker) reconstruct the
    // completion's exact SK, so this is a point lookup, not a range query.
    const completionKey = {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `COMPLETION#${marker.completedAt}#${marker.completionId}`,
    };
    const completionResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: completionKey })
    );
    const completion = completionResult.Item;
    if (!completion) {
      // The marker points at a completion that's gone -- nothing sane to
      // reverse.
      return json(200, { reversed: false });
    }

    const reversalSetParts = ['reversedAt = :now', 'reversedByUID = :uid'];
    const reversalValues: Record<string, unknown> = { ':now': new Date().toISOString(), ':uid': uid };
    if (note !== undefined) {
      reversalSetParts.push('reversalNote = :note');
      reversalValues[':note'] = note;
    }

    try {
      await ddb.send(
        new TransactWriteCommand({
          TransactItems: [
            {
              // The single guard: if two different items on the same
              // completed checklist are unchecked at once, only one of
              // these conditions holds.
              Update: {
                TableName: TABLE_NAME,
                Key: completionKey,
                UpdateExpression: `SET ${reversalSetParts.join(', ')}`,
                ConditionExpression: 'attribute_not_exists(reversedAt)',
                ExpressionAttributeValues: reversalValues,
              },
            },
            {
              // The exact amount originally credited, from the completion
              // itself -- never re-read from the chore's current points,
              // which may have changed since. Uncapped: the balance can go
              // negative if those points were already spent.
              Update: {
                TableName: TABLE_NAME,
                Key: Keys.balance(householdId, completion.completedByUID),
                UpdateExpression: 'ADD #balance :points',
                ExpressionAttributeNames: { '#balance': 'balance' },
                ExpressionAttributeValues: { ':points': -Number(completion.pointsAwarded) },
              },
            },
            {
              // Clears the once-per-day guard so the chore can complete
              // again once every item is re-checked.
              Delete: {
                TableName: TABLE_NAME,
                Key: Keys.completionMarker(householdId, choreId, scheduledDate),
                ConditionExpression: 'completionId = :completionId',
                ExpressionAttributeValues: { ':completionId': marker.completionId },
              },
            },
          ],
        })
      );
      return json(200, { reversed: true });
    } catch (error) {
      if (error instanceof Error && error.name === 'TransactionCanceledException') {
        // A concurrent uncheck already reversed this completion.
        return json(200, { reversed: false });
      }
      throw error;
    }
  } catch (error) {
    return errorResponse(error);
  }
};
