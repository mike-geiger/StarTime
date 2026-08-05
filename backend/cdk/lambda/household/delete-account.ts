import type { APIGatewayProxyHandler } from 'aws-lambda';
import {
  BatchWriteCommand,
  DeleteCommand,
  GetCommand,
  QueryCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid } from '../common/auth';
import { json, errorResponse } from '../common/http';

type Key = { PK: string; SK: string };

/**
 * Collects every item under a household whose SK starts with `prefix`.
 * Paginates -- Query caps at 1MB per page regardless of item count.
 */
async function queryKeysByPrefix(householdId: string, prefix: string): Promise<Key[]> {
  const keys: Key[] = [];
  let lastEvaluatedKey: Record<string, unknown> | undefined;

  do {
    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
        ExpressionAttributeValues: { ':pk': `HOUSEHOLD#${householdId}`, ':prefix': prefix },
        ProjectionExpression: 'PK, SK',
        ExclusiveStartKey: lastEvaluatedKey,
      })
    );
    for (const item of result.Items ?? []) {
      keys.push({ PK: item.PK, SK: item.SK });
    }
    lastEvaluatedKey = result.LastEvaluatedKey;
  } while (lastEvaluatedKey);

  return keys;
}

/**
 * BatchWriteItem caps at 25 items per call (vs Firestore's 500-per-batch),
 * so this needs an explicit chunking loop -- not a 1:1 translation of the
 * old `deleteAllDocuments`. Also retries UnprocessedItems, which DynamoDB
 * can return under throttling even on an otherwise-successful call.
 */
async function batchDelete(keys: Key[]): Promise<void> {
  for (let i = 0; i < keys.length; i += 25) {
    let requests = keys.slice(i, i + 25).map((Key) => ({ DeleteRequest: { Key } }));

    for (let attempt = 0; attempt < 5 && requests.length > 0; attempt++) {
      const result = await ddb.send(
        new BatchWriteCommand({ RequestItems: { [TABLE_NAME]: requests } })
      );
      const unprocessed = result.UnprocessedItems?.[TABLE_NAME] ?? [];
      if (unprocessed.length === 0) break;
      requests = unprocessed as typeof requests;
      await new Promise((resolve) => setTimeout(resolve, 50 * 2 ** attempt));
    }
  }
}

/**
 * Combines the old `leaveHousehold` + `deleteUserProfile` into one call --
 * they were only ever invoked together, back to back, from
 * HouseholdStore.deleteAccountData.
 *
 * The ordering contract matters and is preserved exactly: all household data
 * must be fully cleaned up before the caller deletes the Cognito user. The
 * client still gates Auth deletion on this endpoint returning 2xx, because a
 * partial failure here previously orphaned household data (regression test:
 * testStage5AccountDeletionActuallyDeletesHouseholdData).
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const uid = callerUid(event);

    const profileResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: Keys.userProfile(uid) })
    );
    const householdId: string | undefined = profileResult.Item?.householdId;

    if (householdId) {
      const householdResult = await ddb.send(
        new GetCommand({ TableName: TABLE_NAME, Key: Keys.household(householdId) })
      );
      const household = householdResult.Item;

      if (household) {
        const members: Record<string, unknown> = household.members ?? {};
        const remainingMembers = Object.keys(members).filter((k) => k !== uid);

        if (remainingMembers.length > 0) {
          // Not the last member -- just drop this member, no cascade.
          await ddb.send(
            new UpdateCommand({
              TableName: TABLE_NAME,
              Key: Keys.household(householdId),
              UpdateExpression: 'REMOVE #members.#uid',
              ExpressionAttributeNames: { '#members': 'members', '#uid': uid },
            })
          );
        } else {
          // Last member out -- cascade, in the same order as the Firestore
          // original (completions, redemptions, chores, rewards, invite
          // codes, then the household itself). Order matters: the household
          // doc is deleted last so a failure partway through still leaves a
          // household to retry against rather than orphaned children.
          for (const prefix of ['COMPLETION#', 'REDEMPTION#', 'CHORE#', 'REWARD#', 'BALANCE#']) {
            await batchDelete(await queryKeysByPrefix(householdId, prefix));
          }

          // Invite codes live under their own PK (INVITECODE#{code}), so they
          // need the GSI1 lookup rather than a prefix query on the household.
          const codesResult = await ddb.send(
            new QueryCommand({
              TableName: TABLE_NAME,
              IndexName: 'GSI1',
              KeyConditionExpression: 'GSI1PK = :pk',
              ExpressionAttributeValues: { ':pk': `HOUSEHOLD#${householdId}` },
              ProjectionExpression: 'PK, SK',
            })
          );
          await batchDelete((codesResult.Items ?? []).map((i) => ({ PK: i.PK, SK: i.SK })));

          await ddb.send(
            new DeleteCommand({ TableName: TABLE_NAME, Key: Keys.household(householdId) })
          );
        }
      }
    }

    await ddb.send(new DeleteCommand({ TableName: TABLE_NAME, Key: Keys.userProfile(uid) }));

    return json(204, {});
  } catch (error) {
    return errorResponse(error);
  }
};
