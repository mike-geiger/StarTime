import type { APIGatewayProxyHandler } from 'aws-lambda';
import { DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb } from '../common/dynamo';

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE!;

export const handler: APIGatewayProxyHandler = async (event) => {
  // Best-effort: $disconnect isn't guaranteed to fire (a dropped network
  // never sends one), which is what the TTL in connect.ts is there to cover.
  await ddb.send(
    new DeleteCommand({
      TableName: CONNECTIONS_TABLE,
      Key: { connectionId: event.requestContext.connectionId! },
    })
  );

  return { statusCode: 200, body: 'Disconnected' };
};
