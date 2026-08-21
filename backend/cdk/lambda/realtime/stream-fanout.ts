import type { DynamoDBStreamHandler } from 'aws-lambda';
import { QueryCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import {
  ApiGatewayManagementApiClient,
  PostToConnectionCommand,
} from '@aws-sdk/client-apigatewaymanagementapi';
import { ddb } from '../common/dynamo';

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE!;
const management = new ApiGatewayManagementApiClient({
  endpoint: process.env.WEBSOCKET_ENDPOINT!,
});

/**
 * Which client-side collection a changed item belongs to. Clients get told
 * *what* changed, not the change itself -- see the note on invalidation
 * below.
 */
function resourceFor(sortKey: string): string | null {
  if (sortKey === 'METADATA') return 'household';
  if (sortKey.startsWith('CHORE#')) return 'chores';
  // Checklist progress rides the same invalidation as chores -- ChoreStore
  // already refetches both chores and completions on it.
  if (sortKey.startsWith('CHECKLIST#')) return 'chores';
  if (sortKey.startsWith('COMPLETION#')) return 'completions';
  if (sortKey.startsWith('REWARD#')) return 'rewards';
  if (sortKey.startsWith('REDEMPTION#')) return 'redemptions';
  if (sortKey.startsWith('BALANCE#')) return 'balances';
  return null;
}

/**
 * Pushes lightweight invalidation signals -- `{"type":"invalidate",
 * "resource":"chores"}` -- rather than the changed items themselves.
 *
 * The client already knows how to fetch each collection, so telling it
 * "chores changed, refetch" avoids every hard part of delta sync: merge
 * order, reconciling a pushed delta against an in-flight write, and items
 * that arrive out of order. At this app's scale the extra round-trip costs
 * nothing. Deltas remain an option later without changing the transport.
 */
export const handler: DynamoDBStreamHandler = async (event) => {
  // Collapse the batch: ten completions in one batch should produce one
  // "completions changed" message per household, not ten.
  const byHousehold = new Map<string, Set<string>>();

  for (const record of event.Records) {
    const keys = record.dynamodb?.Keys;
    const pk = keys?.PK?.S;
    const sk = keys?.SK?.S;
    if (!pk?.startsWith('HOUSEHOLD#') || !sk) continue;

    const resource = resourceFor(sk);
    if (!resource) continue;

    const householdId = pk.slice('HOUSEHOLD#'.length);
    if (!byHousehold.has(householdId)) byHousehold.set(householdId, new Set());
    byHousehold.get(householdId)!.add(resource);
  }

  await Promise.all(
    [...byHousehold].map(async ([householdId, resources]) => {
      const connections = await ddb.send(
        new QueryCommand({
          TableName: CONNECTIONS_TABLE,
          IndexName: 'GSI1',
          KeyConditionExpression: 'GSI1PK = :pk',
          ExpressionAttributeValues: { ':pk': `HOUSEHOLD#${householdId}` },
          ProjectionExpression: 'connectionId',
        })
      );

      const payload = Buffer.from(
        JSON.stringify({ type: 'invalidate', resources: [...resources] })
      );

      await Promise.all(
        (connections.Items ?? []).map(async (item) => {
          const connectionId = item.connectionId as string;
          try {
            await management.send(
              new PostToConnectionCommand({ ConnectionId: connectionId, Data: payload })
            );
          } catch (error) {
            // 410 Gone means the client disconnected without a $disconnect
            // reaching us -- clean up so the row doesn't linger until TTL.
            const status = (error as { $metadata?: { httpStatusCode?: number } })?.$metadata
              ?.httpStatusCode;
            if (status === 410) {
              await ddb.send(
                new DeleteCommand({ TableName: CONNECTIONS_TABLE, Key: { connectionId } })
              );
            } else {
              // Don't let one bad connection fail the whole batch: the stream
              // would retry it and re-notify everyone else.
              console.error(`postToConnection failed for ${connectionId}`, error);
            }
          }
        })
      );
    })
  );
};
