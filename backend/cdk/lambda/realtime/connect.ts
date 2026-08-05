import type { APIGatewayProxyHandler } from 'aws-lambda';
import { GetCommand, PutCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE!;
/// Long enough that a normal session never expires mid-use; short enough that
/// rows from connections that vanished without a $disconnect (backgrounded
/// app, dropped network) don't accumulate forever.
const TTL_SECONDS = 12 * 60 * 60;

export const handler: APIGatewayProxyHandler = async (event) => {
  const connectionId = event.requestContext.connectionId!;
  const uid = (event.requestContext.authorizer as { uid?: string } | undefined)?.uid;

  if (!uid) {
    return { statusCode: 401, body: 'Unauthorized' };
  }

  // Fan-out is scoped by household, so the connection has to be tagged with
  // one at handshake time -- the stream handler has no way to resolve a
  // connection's household later.
  const profile = await ddb.send(
    new GetCommand({ TableName: TABLE_NAME, Key: Keys.userProfile(uid) })
  );
  const householdId = profile.Item?.householdId;
  if (!householdId) {
    // Signed in but not in a household yet: nothing to push, so refuse the
    // socket rather than hold an unroutable connection open.
    return { statusCode: 403, body: 'No household' };
  }

  await ddb.send(
    new PutCommand({
      TableName: CONNECTIONS_TABLE,
      Item: {
        connectionId,
        uid,
        householdId,
        // GSI1 lets the stream handler find every connection for a household.
        GSI1PK: `HOUSEHOLD#${householdId}`,
        connectedAt: new Date().toISOString(),
        expiresAt: Math.floor(Date.now() / 1000) + TTL_SECONDS,
      },
    })
  );

  return { statusCode: 200, body: 'Connected' };
};
