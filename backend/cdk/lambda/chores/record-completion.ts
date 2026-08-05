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

    // The completion and the balance credit move together -- balances are a
    // denormalized counter now rather than a sum recomputed from the whole
    // ledger, so they must never drift from the ledger that justifies them.
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
        ],
      })
    );

    const { PK, SK, ...body } = completion;
    return json(201, { completion: body });
  } catch (error) {
    return errorResponse(error);
  }
};
