import type { APIGatewayProxyHandler } from 'aws-lambda';
import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid } from '../common/auth';
import { json, errorResponse } from '../common/http';

/**
 * Combines what used to be two Firestore reads (`fetchProfile` then
 * `fetchHousehold`) into one round-trip. A missing profile is `null`, not an
 * error -- "no profile yet" is the expected state for a brand-new sign-up,
 * matching the old `fetchProfile` Optional-decode behavior.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);

    const profileResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: Keys.userProfile(uid) })
    );
    const profile = profileResult.Item;
    if (!profile) {
      return json(200, { profile: null, household: null });
    }

    let household = null;
    if (profile.householdId) {
      const householdResult = await ddb.send(
        new GetCommand({ TableName: TABLE_NAME, Key: Keys.household(profile.householdId) })
      );
      household = householdResult.Item ?? null;
    }

    return json(200, {
      profile: { name: profile.name, householdId: profile.householdId ?? null, role: profile.role ?? null },
      household: household && {
        id: household.id,
        name: household.name,
        members: household.members,
        lastJoinCode: household.lastJoinCode ?? null,
        createdAt: household.createdAt,
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
};
