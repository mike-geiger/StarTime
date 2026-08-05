import type { APIGatewayProxyHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import { PutCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

/** Create (POST) and update (PUT with rewardId) -- see save-chore.ts. */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const body = JSON.parse(event.body ?? '{}');
    const rewardId = event.pathParameters?.rewardId ?? randomUUID();

    const { name, icon, pointCost, isActive } = body;
    if (!name || !icon || typeof pointCost !== 'number') {
      throw new HttpError(400, 'name, icon and pointCost are required');
    }

    const item = {
      ...Keys.reward(householdId, rewardId),
      id: rewardId,
      name,
      icon,
      pointCost,
      isActive: isActive ?? true,
      createdAt: body.createdAt ?? new Date().toISOString(),
    };

    await ddb.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));

    const { PK, SK, ...reward } = item;
    return json(event.pathParameters?.rewardId ? 200 : 201, { reward });
  } catch (error) {
    return errorResponse(error);
  }
};
