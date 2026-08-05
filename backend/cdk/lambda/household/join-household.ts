import type { APIGatewayProxyHandler } from 'aws-lambda';
import { GetCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);
    const { code, displayName } = JSON.parse(event.body ?? '{}');
    if (!code || !displayName) {
      throw new HttpError(400, 'code and displayName are required');
    }

    const inviteResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: Keys.inviteCode(code) })
    );
    const invite = inviteResult.Item;
    // 404 maps to HouseholdServiceError.invalidCode client-side, preserving
    // the user-facing "That invite code isn't valid" message.
    if (!invite) {
      throw new HttpError(404, "That invite code isn't valid. Double-check it and try again.");
    }

    const householdId: string = invite.householdId;
    const role: string = invite.role;

    await ddb.send(
      new TransactWriteCommand({
        TransactItems: [
          {
            // Dotted-path member insert, equivalent to Firestore's
            // `updateData(["members.\(uid)": ...])` partial map update --
            // the condition guards against the household having been
            // cascade-deleted between the invite lookup and this write.
            Update: {
              TableName: TABLE_NAME,
              Key: Keys.household(householdId),
              UpdateExpression: 'SET #members.#uid = :member, lastJoinCode = :code',
              ConditionExpression: 'attribute_exists(PK)',
              ExpressionAttributeNames: { '#members': 'members', '#uid': uid },
              ExpressionAttributeValues: {
                ':member': { name: displayName, role },
                ':code': code,
              },
            },
          },
          {
            Put: {
              TableName: TABLE_NAME,
              Item: {
                ...Keys.userProfile(uid),
                name: displayName,
                householdId,
                role,
                createdAt: new Date().toISOString(),
              },
            },
          },
        ],
      })
    );

    const householdResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: Keys.household(householdId) })
    );
    const household = householdResult.Item!;

    return json(200, {
      household: {
        id: household.id,
        name: household.name,
        members: household.members,
        lastJoinCode: household.lastJoinCode ?? null,
        createdAt: household.createdAt,
      },
    });
  } catch (error) {
    // A stale code pointing at an already-deleted household fails the
    // transaction's ConditionExpression -- surface it as the same
    // user-facing "invalid code" message rather than a 500.
    if (error instanceof Error && error.name === 'TransactionCanceledException') {
      return errorResponse(
        new HttpError(404, "That invite code isn't valid. Double-check it and try again.")
      );
    }
    return errorResponse(error);
  }
};
