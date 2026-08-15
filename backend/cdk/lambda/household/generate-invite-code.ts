import type { APIGatewayProxyHandler } from 'aws-lambda';
import { PutCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, requireParent, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

// Same alphabet as the old client-side generator: no 0/O/1/I, since codes
// get read aloud and typed by hand.
const CODE_CHARACTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;
const MAX_ATTEMPTS = 5;

function randomCode(): string {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_CHARACTERS[Math.floor(Math.random() * CODE_CHARACTERS.length)];
  }
  return code;
}

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);
    const householdId = await callerHouseholdId(uid);
    const { role } = JSON.parse(event.body ?? '{}');
    if (role !== 'parent' && role !== 'child') {
      throw new HttpError(400, 'role must be "parent" or "child"');
    }

    // Only parents can invite. Previously this was enforced solely by
    // SettingsView hiding the buttons for children -- now it's a real
    // server-side check, which is the whole point of moving authorization
    // out of console-only security rules and into version-controlled code.
    await requireParent(householdId, uid, 'Only parents can generate invite codes');

    // The old client-side generator never checked for collisions. A
    // conditional Put makes a collision a retry instead of silently
    // repointing an existing code at a different household.
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const code = randomCode();
      try {
        await ddb.send(
          new PutCommand({
            TableName: TABLE_NAME,
            Item: {
              ...Keys.inviteCode(code),
              householdId,
              role,
              createdByUID: uid,
              createdAt: new Date().toISOString(),
              // GSI1 is what lets the cascade delete find every code for a
              // household (Firestore's whereField("householdId", ...) equivalent).
              GSI1PK: `HOUSEHOLD#${householdId}`,
              GSI1SK: `INVITECODE#${code}`,
            },
            ConditionExpression: 'attribute_not_exists(PK)',
          })
        );
        return json(201, { code });
      } catch (error) {
        if (error instanceof Error && error.name === 'ConditionalCheckFailedException') {
          continue;
        }
        throw error;
      }
    }

    throw new HttpError(503, 'Could not generate a unique invite code. Please try again.');
  } catch (error) {
    return errorResponse(error);
  }
};
