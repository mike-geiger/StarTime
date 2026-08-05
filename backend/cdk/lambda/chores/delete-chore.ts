import type { APIGatewayProxyHandler } from 'aws-lambda';
import { DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const choreId = event.pathParameters?.choreId;
    if (!choreId) {
      throw new HttpError(400, 'choreId is required');
    }

    // Keyed by the caller's own householdId, so a client can only ever
    // delete a chore in their own household regardless of what id they pass.
    await ddb.send(
      new DeleteCommand({ TableName: TABLE_NAME, Key: Keys.chore(householdId, choreId) })
    );

    return json(204, {});
  } catch (error) {
    return errorResponse(error);
  }
};
