import type { APIGatewayProxyHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import { TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const { choreId, choreTitle, pointsAwarded, completedByUID, completedByName, scheduledDate } =
      JSON.parse(event.body ?? '{}');

    if (!choreId || !choreTitle || typeof pointsAwarded !== 'number' || !completedByUID || !scheduledDate) {
      throw new HttpError(400, 'choreId, choreTitle, pointsAwarded, completedByUID and scheduledDate are required');
    }

    const id = randomUUID();
    const completedAt = new Date().toISOString();

    const completion = {
      PK: `HOUSEHOLD#${householdId}`,
      // Timestamp-first sort key makes "completions since X" a range query
      // rather than a filtered scan; the uuid suffix keeps two completions
      // in the same millisecond from colliding.
      SK: `COMPLETION#${completedAt}#${id}`,
      id,
      choreId,
      choreTitle,
      pointsAwarded,
      completedByUID,
      completedByName,
      completedAt,
      scheduledDate,
    };

    // The completion, the balance credit, and the once-per-day marker all
    // move together. Balances are a denormalized counter rather than a sum
    // recomputed from the ledger, so they must never drift from the ledger
    // that justifies them.
    try {
      await ddb.send(
        new TransactWriteCommand({
          TransactItems: [
            { Put: { TableName: TABLE_NAME, Item: completion } },
            {
              Update: {
                TableName: TABLE_NAME,
                Key: Keys.balance(householdId, completedByUID),
                // Earning is unconditional -- no balance check, unlike redeem.
                UpdateExpression: 'ADD #balance :points SET #uid = :uid',
                ExpressionAttributeNames: { '#balance': 'balance', '#uid': 'uid' },
                ExpressionAttributeValues: { ':points': pointsAwarded, ':uid': completedByUID },
              },
            },
            {
              // The uniqueness constraint. A completion's own sort key carries
              // a timestamp and a uuid, so it can never collide -- this marker
              // is what makes "one completion per chore per day" enforceable,
              // which is what `scheduledDate` was always meant to guarantee.
              // Previously only the client checked, so a double-tap (or two
              // devices at once) double-credited the points.
              Put: {
                TableName: TABLE_NAME,
                Item: {
                  ...Keys.completionMarker(householdId, choreId, scheduledDate),
                  choreId,
                  scheduledDate,
                  completionId: id,
                },
                ConditionExpression: 'attribute_not_exists(PK)',
              },
            },
          ],
        })
      );
    } catch (error) {
      if (error instanceof Error && error.name === 'TransactionCanceledException') {
        throw new HttpError(409, 'That chore is already done today.');
      }
      throw error;
    }

    const { PK, SK, ...body } = completion;
    return json(201, { completion: body });
  } catch (error) {
    return errorResponse(error);
  }
};
