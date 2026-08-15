import type { APIGatewayProxyEvent } from 'aws-lambda';
import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from './dynamo';

export class HttpError extends Error {
  constructor(public statusCode: number, message: string) {
    super(message);
  }
}

/**
 * The caller's canonical app-level user id, from the ID token claims the
 * REST API's Cognito authorizer already validated -- never taken from a
 * request body/path param, so no Lambda has to trust a client-supplied uid.
 */
export function callerUid(event: APIGatewayProxyEvent): string {
  const claims = event.requestContext.authorizer?.claims;
  const uid = claims?.['custom:legacy_uid'];
  if (typeof uid !== 'string' || !uid) {
    throw new HttpError(401, 'Missing or invalid caller identity');
  }
  return uid;
}

/** Re-derives the caller's householdId server-side from their own profile. */
export async function callerHouseholdId(uid: string): Promise<string> {
  const result = await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: Keys.userProfile(uid) }));
  const householdId = result.Item?.householdId;
  if (typeof householdId !== 'string' || !householdId) {
    throw new HttpError(404, 'No household found for the current user');
  }
  return householdId;
}

/**
 * Throws 403 unless the caller holds the parent role in the given household.
 *
 * The household's own member map is the authority here, not the copy of
 * `role` on the user profile item -- the profile's is a per-user convenience
 * denormalization, while the member map is the household's record of who its
 * parents are. Callers pass a householdId they derived from
 * `callerHouseholdId`, so this never widens what the caller could reach.
 */
export async function requireParent(
  householdId: string,
  uid: string,
  message: string
): Promise<{ name: string; role: string }> {
  const result = await ddb.send(
    new GetCommand({ TableName: TABLE_NAME, Key: Keys.household(householdId) })
  );
  const member = result.Item?.members?.[uid];
  if (member?.role !== 'parent') {
    throw new HttpError(403, message);
  }
  // Returned so callers that need to attribute an action to this parent
  // don't have to read the household a second time.
  return member;
}
