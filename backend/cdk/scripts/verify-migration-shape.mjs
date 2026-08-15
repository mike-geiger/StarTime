#!/usr/bin/env node
/**
 * Storage-shape contract test: writes items directly into DynamoDB, bypassing
 * every handler, then reads them back through the real REST API as a real
 * signed-in user.
 *
 * This catches the class of bug the UI tests structurally cannot, because
 * they only ever read back what the handlers themselves just wrote: a sort
 * key that falls outside a query's range, a missing GSI attribute, a field
 * a handler expects under a different name. Anything that writes to the
 * table without going through the API -- a backfill, a repair script, a
 * restore -- depends on the assumptions asserted here.
 *
 * It began as the pre-cutover rehearsal for the Firestore migration, which
 * is why the seeded items carry ids in the old provider's format. That is
 * now just a fixture, not a dependency; nothing here touches Firebase.
 *
 * Expects the env vars with-ephemeral-stack.sh exports.
 */
import {
  CognitoIdentityProviderClient,
  SignUpCommand,
  InitiateAuthCommand,
} from '@aws-sdk/client-cognito-identity-provider';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, BatchWriteCommand } from '@aws-sdk/lib-dynamodb';

const {
  STARTIME_USER_POOL_CLIENT_ID: CLIENT_ID,
  STARTIME_API_BASE_URL: API_URL,
  STARTIME_TABLE_NAME: TABLE,
  AWS_REGION = 'us-west-2',
} = process.env;

if (!CLIENT_ID || !API_URL || !TABLE) {
  console.error('Missing STARTIME_USER_POOL_CLIENT_ID / STARTIME_API_BASE_URL / STARTIME_TABLE_NAME');
  process.exit(1);
}

const cognito = new CognitoIdentityProviderClient({ region: AWS_REGION });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: AWS_REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

let failures = 0;
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : ` -- got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`}`);
  if (!ok) failures++;
};

// 1. A real Cognito user, because the API derives identity from the token.
const email = `migshape-${Date.now()}@example.com`;
const password = 'TempPass123!';
console.log('1. signing up', email);
await cognito.send(new SignUpCommand({ ClientId: CLIENT_ID, Username: email, Password: password }));
const auth = await cognito.send(
  new InitiateAuthCommand({
    ClientId: CLIENT_ID,
    AuthFlow: 'USER_PASSWORD_AUTH',
    AuthParameters: { USERNAME: email, PASSWORD: password },
  })
);
const idToken = auth.AuthenticationResult.IdToken;
const claims = JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString());
// The migration preserves Firebase UIDs verbatim, and migrate-user assigns
// that same value as custom:legacy_uid -- so at cutover these are equal.
const uid = claims['custom:legacy_uid'];
console.log('   legacy_uid:', uid);

// 2. Seed migrated-shaped items. Mirrors migrate-firestore-to-dynamodb.mjs.
const householdId = 'legacy-household-id';
const choreId = 'legacy-chore-id';
const rewardId = 'legacy-reward-id';
const completedAt = '2026-07-01T12:00:00.000Z';
const redeemedAt = '2026-07-02T12:00:00.000Z';

const items = [
  { PK: `USER#${uid}`, SK: 'PROFILE', name: 'Dad', householdId, role: 'parent', createdAt: '2026-06-01T00:00:00.000Z' },
  {
    PK: `HOUSEHOLD#${householdId}`, SK: 'METADATA', id: householdId, name: 'The Geigers',
    members: { [uid]: { name: 'Dad', role: 'parent' } },
    lastJoinCode: 'ABC123', createdAt: '2026-06-01T00:00:00.000Z',
  },
  {
    PK: `HOUSEHOLD#${householdId}`, SK: `CHORE#${choreId}`, id: choreId, title: 'Make bed',
    icon: 'bed.double.fill', points: 10, recurrence: 'daily', weeklyDays: [],
    assignedToUID: uid, isActive: true, createdAt: '2026-06-01T00:00:00.000Z',
  },
  {
    PK: `HOUSEHOLD#${householdId}`, SK: `COMPLETION#${completedAt}#legacy-completion-id`,
    id: 'legacy-completion-id', choreId, choreTitle: 'Make bed', pointsAwarded: 10,
    completedByUID: uid, completedByName: 'Dad', completedAt, scheduledDate: '2026-07-01',
  },
  {
    PK: `HOUSEHOLD#${householdId}`, SK: `REWARD#${rewardId}`, id: rewardId, name: 'Ice cream',
    icon: 'gift.fill', pointCost: 4, isActive: true, createdAt: '2026-06-01T00:00:00.000Z',
  },
  {
    PK: `HOUSEHOLD#${householdId}`, SK: `REDEMPTION#${redeemedAt}#legacy-redemption-id`,
    id: 'legacy-redemption-id', rewardId, rewardName: 'Ice cream', pointsSpent: 4,
    redeemedByUID: uid, redeemedByName: 'Dad', redeemedAt,
  },
  // earned 10 - spent 4 = 6, the formula the migration replicates
  { PK: `HOUSEHOLD#${householdId}`, SK: `BALANCE#${uid}`, uid, balance: 6 },
  {
    PK: 'INVITECODE#ABC123', SK: 'METADATA', householdId, role: 'child', createdByUID: uid,
    createdAt: '2026-06-01T00:00:00.000Z',
    GSI1PK: `HOUSEHOLD#${householdId}`, GSI1SK: 'INVITECODE#ABC123',
  },
];

console.log(`2. seeding ${items.length} migrated-shaped items into ${TABLE}`);
await ddb.send(
  new BatchWriteCommand({ RequestItems: { [TABLE]: items.map((Item) => ({ PutRequest: { Item } })) } })
);

// 3. Read it all back through the real API.
const api = async (method, path) => {
  const res = await fetch(`${API_URL.replace(/\/$/, '')}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${idToken}` },
  });
  if (!res.ok) {
    console.log(`  FAIL ${method} ${path} -> ${res.status} ${await res.text()}`);
    failures++;
    return null;
  }
  return res.json();
};

console.log('3. reading back through the API');
const me = await api('GET', 'households/me');
check('household name', me?.household?.name, 'The Geigers');
check('household id', me?.household?.id, householdId);
check('profile role', me?.profile?.role, 'parent');
check('member name', me?.household?.members?.[uid]?.name, 'Dad');

const chores = await api('GET', 'chores');
check('chore count', chores?.chores?.length, 1);
check('chore title', chores?.chores?.[0]?.title, 'Make bed');

// The 60-day-window query the app actually issues -- catches a sort key
// that sorts outside the intended range.
const since = new Date(Date.parse(completedAt) - 86_400_000).toISOString();
const windowed = await api('GET', `completions?since=${encodeURIComponent(since)}`);
check('completion in since-window', windowed?.completions?.length, 1);

const allCompletions = await api('GET', 'completions');
check('completion (unwindowed)', allCompletions?.completions?.[0]?.pointsAwarded, 10);

const rewards = await api('GET', 'rewards');
check('reward name', rewards?.rewards?.[0]?.name, 'Ice cream');

const redemptions = await api('GET', 'redemptions');
check('redemption points', redemptions?.redemptions?.[0]?.pointsSpent, 4);
// The seeded row carries no `status` -- the pre-fulfillment-tracking shape.
// Every such redemption was complete the moment it was made, so it has to
// read back as fulfilled or migrated families would open the app to a queue
// of obligations they already met.
check('status-less redemption reads as fulfilled', redemptions?.redemptions?.[0]?.status, 'fulfilled');

const balances = await api('GET', 'balances');
check('migrated balance', balances?.balances?.[uid], 6);

// 4. Cascade delete must find the migrated invite code via GSI1 -- a missing
// GSI attribute on migrated rows would orphan codes at account deletion.
console.log('4. deleting account (cascade must sweep the migrated invite code)');
const del = await fetch(`${API_URL.replace(/\/$/, '')}/account`, {
  method: 'DELETE',
  headers: { Authorization: `Bearer ${idToken}` },
});
check('delete status', del.status, 204);

const { GetCommand } = await import('@aws-sdk/lib-dynamodb');
const leftoverCode = await ddb.send(
  new GetCommand({ TableName: TABLE, Key: { PK: 'INVITECODE#ABC123', SK: 'METADATA' } })
);
check('invite code cascade-deleted', leftoverCode.Item, undefined);
const leftoverHousehold = await ddb.send(
  new GetCommand({ TableName: TABLE, Key: { PK: `HOUSEHOLD#${householdId}`, SK: 'METADATA' } })
);
check('household cascade-deleted', leftoverHousehold.Item, undefined);

console.log(failures === 0 ? '\nMIGRATION SHAPE OK' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
