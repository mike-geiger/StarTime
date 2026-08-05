import type { APIGatewayProxyHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import { TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);
    const { name, displayName } = JSON.parse(event.body ?? '{}');
    if (!name || !displayName) {
      throw new HttpError(400, 'name and displayName are required');
    }

    const householdId = randomUUID();
    const createdAt = new Date().toISOString();
    const household = {
      ...Keys.household(householdId),
      id: householdId,
      name,
      members: { [uid]: { name: displayName, role: 'parent' } },
      createdAt,
    };
    const profile = {
      ...Keys.userProfile(uid),
      name: displayName,
      householdId,
      role: 'parent',
      createdAt,
    };

    // One transaction rather than the two unbatched Firestore writes this
    // replaces -- a half-created household with no profile pointing at it
    // (or vice versa) was always a latent failure mode there.
    await ddb.send(
      new TransactWriteCommand({
        TransactItems: [
          { Put: { TableName: TABLE_NAME, Item: household } },
          { Put: { TableName: TABLE_NAME, Item: profile } },
        ],
      })
    );

    return json(201, {
      household: { id: householdId, name, members: household.members, lastJoinCode: null, createdAt },
    });
  } catch (error) {
    return errorResponse(error);
  }
};
