import { QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME } from '../common/dynamo';

export type RedemptionStatus = 'pending' | 'fulfilled' | 'cancelled';

export const REDEMPTION_STATUSES: RedemptionStatus[] = ['pending', 'fulfilled', 'cancelled'];

/**
 * What a redemption with no stored `status` means.
 *
 * Every redemption recorded before fulfillment tracking existed was complete
 * the moment it was made -- there was nothing else it could be. Defaulting
 * them to `pending` would hand every existing family a queue of obligations
 * they already met, with no way to tell those from real requests.
 */
export const DEFAULT_STATUS: RedemptionStatus = 'fulfilled';

/**
 * Reads every redemption in a household.
 *
 * The upper bound is not optional: a bare `SK > 'REDEMPTION#'` would also
 * match `REWARD#` and anything else sorting after it under the same PK.
 *
 * `consistent` matters when reading back something just written: Query is
 * eventually consistent by default, so a read immediately after an update
 * can legitimately return the pre-write item.
 */
export async function queryRedemptions(
  householdId: string,
  { consistent = false } = {}
): Promise<Record<string, any>[]> {
  const items: Record<string, any>[] = [];
  let lastEvaluatedKey: Record<string, unknown> | undefined;

  do {
    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'PK = :pk AND SK BETWEEN :lo AND :hi',
        ExpressionAttributeValues: {
          ':pk': `HOUSEHOLD#${householdId}`,
          ':lo': 'REDEMPTION#',
          ':hi': 'REDEMPTION#~',
        },
        ConsistentRead: consistent,
        ExclusiveStartKey: lastEvaluatedKey,
      })
    );
    items.push(...(result.Items ?? []));
    lastEvaluatedKey = result.LastEvaluatedKey;
  } while (lastEvaluatedKey);

  return items;
}

/** Strips the storage keys and fills in the fulfillment state for legacy rows. */
export function presentRedemption(item: Record<string, any>) {
  const { PK, SK, ...body } = item;
  return { ...body, status: (body.status as RedemptionStatus) ?? DEFAULT_STATUS };
}

/**
 * Finds one redemption by its id, within the caller's own household.
 *
 * A redemption's sort key is `REDEMPTION#{redeemedAtISO}#{id}`, so the key
 * cannot be rebuilt from an id alone and this has to be a range query rather
 * than a point read. The alternative -- having the client send `redeemedAt`
 * so the key could be reconstructed -- would mean trusting a client-supplied
 * key component, which no handler here does.
 *
 * Scoping the query to the caller's own household is also what enforces
 * isolation: a redemption in someone else's household simply isn't in the
 * result set, so it comes back undefined and the caller reports it as not
 * found without disclosing that it exists.
 *
 * Returns the raw item, PK/SK included -- callers need the real key to write
 * against it.
 */
export async function findRedemptionById(
  householdId: string,
  redemptionId: string,
  options: { consistent?: boolean } = {}
): Promise<Record<string, any> | undefined> {
  const items = await queryRedemptions(householdId, options);
  return items.find((item) => item.id === redemptionId);
}
