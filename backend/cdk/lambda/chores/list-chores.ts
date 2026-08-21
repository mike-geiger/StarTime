import type { APIGatewayProxyHandler } from 'aws-lambda';
import { QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME } from '../common/dynamo';
import { callerUid, callerHouseholdId } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));

    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
        // Per-household chore counts are tiny, so filtering after the query
        // costs far less than maintaining a sparse GSI on isActive.
        FilterExpression: 'isActive = :true',
        ExpressionAttributeValues: {
          ':pk': `HOUSEHOLD#${householdId}`,
          ':prefix': 'CHORE#',
          ':true': true,
        },
      })
    );

    // A chore written before checklist items existed has no `items`
    // attribute at all -- default it on read, the same "absence defaults
    // to the pre-feature meaning" rule as a status-less redemption, rather
    // than backfilling every existing row.
    const chores = (result.Items ?? []).map((item) => ({ ...item, items: item.items ?? [] }));

    return json(200, { chores });
  } catch (error) {
    return errorResponse(error);
  }
};
