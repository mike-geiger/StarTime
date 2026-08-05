import type { APIGatewayProxyHandler } from 'aws-lambda';
import { DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const rewardId = event.pathParameters?.rewardId;
    if (!rewardId) {
      throw new HttpError(400, 'rewardId is required');
    }

    await ddb.send(
      new DeleteCommand({ TableName: TABLE_NAME, Key: Keys.reward(householdId, rewardId) })
    );

    return json(204, {});
  } catch (error) {
    return errorResponse(error);
  }
};
