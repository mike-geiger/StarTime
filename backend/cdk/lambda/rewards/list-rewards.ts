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
        FilterExpression: 'isActive = :true',
        ExpressionAttributeValues: {
          ':pk': `HOUSEHOLD#${householdId}`,
          ':prefix': 'REWARD#',
          ':true': true,
        },
      })
    );

    return json(200, { rewards: result.Items ?? [] });
  } catch (error) {
    return errorResponse(error);
  }
};
