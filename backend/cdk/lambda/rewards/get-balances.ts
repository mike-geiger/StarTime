import type { APIGatewayProxyHandler } from 'aws-lambda';
import { QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME } from '../common/dynamo';
import { callerUid, callerHouseholdId } from '../common/auth';
import { json, errorResponse } from '../common/http';

/**
 * Every member's balance in one query -- households are small, and the app
 * shows sibling balances side by side, so per-uid lookups would just be N
 * round-trips for the same data.
 *
 * Replaces summing the entire lifetime completion + redemption ledger on the
 * client (the old RewardStore.balance).
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));

    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
        ExpressionAttributeValues: { ':pk': `HOUSEHOLD#${householdId}`, ':prefix': 'BALANCE#' },
      })
    );

    const balances: Record<string, number> = {};
    for (const item of result.Items ?? []) {
      // SK is BALANCE#{uid}; `uid` is also stored as an attribute, but
      // deriving from the key avoids depending on both staying in sync.
      const uid = String(item.SK).slice('BALANCE#'.length);
      balances[uid] = Number(item.balance ?? 0);
    }

    return json(200, { balances });
  } catch (error) {
    return errorResponse(error);
  }
};
