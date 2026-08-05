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

    return json(200, { chores: result.Items ?? [] });
  } catch (error) {
    return errorResponse(error);
  }
};
