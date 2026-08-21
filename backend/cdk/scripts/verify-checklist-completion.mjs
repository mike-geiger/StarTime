#!/usr/bin/env node
/**
 * Proves the checklist-completion design in
 * openspec/changes/add-chore-checklists/design.md: a checklist chore
 * credits its points exactly once, atomically, on whichever check closes
 * the set -- even when two different "last items" are checked at the same
 * moment, or the same item is checked twice. Unchecking after completion
 * reverses it (uncapped balance debit, even into negative territory) without
 * altering anything the original completion recorded. Editing the item list
 * never retroactively completes or un-completes a day, past or present; the
 * explicit complete action is what's needed when an edit already satisfies
 * the checked set. A chore with no items is unaffected -- it still uses
 * today's single-tap flow. Account deletion cascades to checklist progress
 * rows the same as every other per-household item type.
 */
import {
  CognitoIdentityProviderClient,
  SignUpCommand,
  InitiateAuthCommand,
} from '@aws-sdk/client-cognito-identity-provider';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand } from '@aws-sdk/lib-dynamodb';

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

// Direct table access, bypassing every handler -- same technique
// verify-migration-shape.mjs uses -- so cascade delete can be proven
// rather than just trusted from a 204 status.
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: AWS_REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

let failures = 0;
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : ` -- got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`}`);
  if (!ok) failures++;
};

const cognito = new CognitoIdentityProviderClient({ region: AWS_REGION });
const email = `checklist-${Date.now()}@example.com`;
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
const uid = JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString())['custom:legacy_uid'];

const api = async (method, path, body) => {
  const res = await fetch(`${API_URL.replace(/\/$/, '')}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${idToken}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: res.status === 204 ? null : await res.json() };
};

const checkItem = (choreId, itemId, date) =>
  api('POST', `chores/${choreId}/checklist/items/${itemId}/check?scheduledDate=${date}`);
const uncheckItem = (choreId, itemId, date, note) =>
  api(
    'POST',
    `chores/${choreId}/checklist/items/${itemId}/uncheck?scheduledDate=${date}`,
    note !== undefined ? { note } : undefined
  );
const completeChecklist = (choreId, date) =>
  api('POST', `chores/${choreId}/checklist/complete?scheduledDate=${date}`);
const fetchChecklistProgress = async (choreId, date) => {
  const res = await api('GET', `chores/checklist?scheduledDate=${date}`);
  return res.body.checklists.find((c) => c.choreId === choreId);
};

const makeChecklistChore = async (itemTitles, points) => {
  const items = itemTitles.map((title, i) => ({ id: `item-${i}-${Date.now()}-${Math.random().toString(36).slice(2)}`, title }));
  const res = await api('POST', 'chores', {
    title: 'Morning Chores', icon: 'sparkles', points,
    recurrence: 'daily', weeklyDays: [], assignedToUID: uid, isActive: true, items,
  });
  return { choreId: res.body.chore.id, items };
};

console.log('2. creating household');
const household = await api('POST', 'households', { name: 'Checklist Test', displayName: 'Tester' });
const householdId = household.body.household.id;

let totalBalance = 0;

console.log('\n3. sequential check: credit only on the last item');
{
  const { choreId, items } = await makeChecklistChore(['Brush teeth', 'Eat breakfast', 'Practice piano'], 10);
  const date = '2026-08-05';

  const r1 = await checkItem(choreId, items[0].id, date);
  check('check 1/3 succeeds', r1.status, 200);
  check('check 1/3 not yet completed', r1.body.completed, false);

  const r1Again = await checkItem(choreId, items[0].id, date);
  check('checking an already-checked item again is a no-op', r1Again.body.completed, false);
  const progressAfterRepeat = await fetchChecklistProgress(choreId, date);
  check(
    'the checked set is unchanged by re-checking the same item',
    [...progressAfterRepeat.checkedItemIds],
    [items[0].id]
  );

  const r2 = await checkItem(choreId, items[1].id, date);
  check('check 2/3 not yet completed', r2.body.completed, false);

  const progress = await fetchChecklistProgress(choreId, date);
  check(
    'GET checklist progress reflects checked items so far',
    [...progress.checkedItemIds].sort(),
    [items[0].id, items[1].id].sort()
  );

  let balances = await api('GET', 'balances');
  check('no credit before the 3rd check', balances.body.balances[uid] ?? 0, totalBalance);

  const r3 = await checkItem(choreId, items[2].id, date);
  check('check 3/3 completes', r3.body.completed, true);
  totalBalance += 10;

  const completions = await api('GET', 'completions');
  const forChore = completions.body.completions.filter((c) => c.choreId === choreId && c.scheduledDate === date);
  check('exactly one completion recorded', forChore.length, 1);
  check('completion credits full points', forChore[0].pointsAwarded, 10);

  balances = await api('GET', 'balances');
  check('balance credited exactly once', balances.body.balances[uid], totalBalance);
}

console.log('\n4. unchecking before completion is a plain edit, not a reversal');
{
  const { choreId, items } = await makeChecklistChore(['One', 'Two'], 9);
  const date = '2026-08-05b';

  await checkItem(choreId, items[0].id, date);
  const before = await fetchChecklistProgress(choreId, date);
  check('the item is checked before the uncheck', [...before.checkedItemIds], [items[0].id]);

  const un = await uncheckItem(choreId, items[0].id, date);
  check('unchecking an item on a not-yet-completed checklist is not a reversal', un.body.reversed, false);

  const after = await fetchChecklistProgress(choreId, date);
  check('the item is unchecked again', after?.checkedItemIds ?? [], []);

  const completions = await api('GET', 'completions');
  const forChore = completions.body.completions.filter((c) => c.choreId === choreId && c.scheduledDate === date);
  check('no completion was ever recorded for this day', forChore.length, 0);

  const balances = await api('GET', 'balances');
  check('balance unaffected by the pre-completion uncheck', balances.body.balances[uid] ?? 0, totalBalance);
}

console.log('\n5. concurrent race: two different "last items" checked at once');
{
  const { choreId, items } = await makeChecklistChore(['A', 'B', 'C', 'D'], 7);
  const date = '2026-08-06';
  await checkItem(choreId, items[0].id, date);
  await checkItem(choreId, items[1].id, date);

  const [ra, rb] = await Promise.all([
    checkItem(choreId, items[2].id, date),
    checkItem(choreId, items[3].id, date),
  ]);
  const completedCount = [ra, rb].filter((r) => r.body.completed).length;
  check('exactly one request reports completion', completedCount, 1);

  const completions = await api('GET', 'completions');
  const forChore = completions.body.completions.filter((c) => c.choreId === choreId && c.scheduledDate === date);
  check('exactly one completion recorded under concurrency', forChore.length, 1);

  totalBalance += 7;
  const balances = await api('GET', 'balances');
  check('balance credited exactly once under concurrency', balances.body.balances[uid], totalBalance);
}

console.log('\n6. reversal: uncheck after completion, then re-check to complete again');
{
  const { choreId, items } = await makeChecklistChore(['X', 'Y'], 6);
  const date = '2026-08-07';
  await checkItem(choreId, items[0].id, date);
  const closing = await checkItem(choreId, items[1].id, date);
  check('checklist completes', closing.body.completed, true);
  totalBalance += 6;
  let balances = await api('GET', 'balances');
  check('balance credited', balances.body.balances[uid], totalBalance);

  const completionsBeforeReversal = await api('GET', 'completions');
  const original = completionsBeforeReversal.body.completions.find(
    (c) => c.choreId === choreId && c.scheduledDate === date
  );

  const un = await uncheckItem(choreId, items[0].id, date, 'checked by mistake');
  check('uncheck after completion reports a reversal', un.body.reversed, true);
  totalBalance -= 6;

  balances = await api('GET', 'balances');
  check('balance debited back on reversal', balances.body.balances[uid], totalBalance);

  const completions = await api('GET', 'completions');
  const forChore = completions.body.completions.filter((c) => c.choreId === choreId && c.scheduledDate === date);
  check('completion still recorded, one entry', forChore.length, 1);
  check('completion marked reversed', Boolean(forChore[0].reversedAt), true);
  check('reversal note recorded', forChore[0].reversalNote, 'checked by mistake');

  // The reversal only ever SETs reversedAt/reversedByUID/reversalNote --
  // every fact recorded at the original completion must survive untouched.
  check('id unchanged by reversal', forChore[0].id, original.id);
  check('choreTitle unchanged by reversal', forChore[0].choreTitle, original.choreTitle);
  check('pointsAwarded unchanged by reversal', forChore[0].pointsAwarded, original.pointsAwarded);
  check('completedByUID unchanged by reversal', forChore[0].completedByUID, original.completedByUID);
  check('completedByName unchanged by reversal', forChore[0].completedByName, original.completedByName);
  check('completedAt unchanged by reversal', forChore[0].completedAt, original.completedAt);
  check('scheduledDate unchanged by reversal', forChore[0].scheduledDate, original.scheduledDate);

  const recompleted = await checkItem(choreId, items[0].id, date);
  check('re-checking the unchecked item completes again', recompleted.body.completed, true);
  totalBalance += 6;

  balances = await api('GET', 'balances');
  check('balance credited again after re-completion', balances.body.balances[uid], totalBalance);

  const completions2 = await api('GET', 'completions');
  const forChore2 = completions2.body.completions.filter((c) => c.choreId === choreId && c.scheduledDate === date);
  check('two completions now recorded for that day (original + re-completion)', forChore2.length, 2);
}

console.log('\n7. reversal after the points were already spent: balance goes negative');
{
  const { choreId, items } = await makeChecklistChore(['Only item'], 4);
  const date = '2026-08-08';
  const closing = await checkItem(choreId, items[0].id, date);
  check('single-item checklist completes on the only check', closing.body.completed, true);
  totalBalance += 4;

  const reward = await api('POST', 'rewards', { name: 'Spend it', icon: 'gift.fill', pointCost: totalBalance });
  const redeem = await api('POST', 'redemptions', {
    rewardId: reward.body.reward.id, redeemedByUID: uid, redeemedByName: 'Tester',
  });
  check('redemption spends the full balance', redeem.status, 201);
  totalBalance -= reward.body.reward.pointCost;

  let balances = await api('GET', 'balances');
  check('balance is now zero after spending everything', balances.body.balances[uid], totalBalance);

  const un = await uncheckItem(choreId, items[0].id, date);
  check('reversal succeeds even though the points are already spent', un.body.reversed, true);
  totalBalance -= 4;

  balances = await api('GET', 'balances');
  check('balance goes negative rather than being refused or floored', balances.body.balances[uid], totalBalance);
}

console.log('\n8. concurrent reversal race: two different items unchecked at once');
{
  const { choreId, items } = await makeChecklistChore(['P', 'Q'], 5);
  const date = '2026-08-09';
  await checkItem(choreId, items[0].id, date);
  const closing = await checkItem(choreId, items[1].id, date);
  check('checklist completes', closing.body.completed, true);
  totalBalance += 5;

  const [ua, ub] = await Promise.all([
    uncheckItem(choreId, items[0].id, date),
    uncheckItem(choreId, items[1].id, date),
  ]);
  const reversedCount = [ua, ub].filter((r) => r.body.reversed).length;
  check('exactly one reversal under concurrency', reversedCount, 1);
  totalBalance -= 5;

  const balances = await api('GET', 'balances');
  check('balance debited exactly once under concurrent reversal', balances.body.balances[uid], totalBalance);

  const completions = await api('GET', 'completions');
  const forChore = completions.body.completions.filter((c) => c.choreId === choreId && c.scheduledDate === date);
  check('still exactly one completion record (reversed, not duplicated)', forChore.length, 1);
}

console.log('\n9. editing items never auto-completes; explicit complete action is required');
{
  const { choreId, items } = await makeChecklistChore(['One', 'Two', 'Three'], 8);
  const date = '2026-08-10';
  await checkItem(choreId, items[0].id, date);
  await checkItem(choreId, items[1].id, date);
  // items[2] never checked.

  const early = await completeChecklist(choreId, date);
  check('explicit complete refused while incomplete', early.status, 409);

  // Remove the still-unchecked item -- the checked set (items 0, 1) now
  // covers what's left required.
  const choreGet = await api('GET', 'chores');
  const chore = choreGet.body.chores.find((c) => c.id === choreId);
  await api('PUT', `chores/${choreId}`, { ...chore, items: [items[0], items[1]] });

  const balancesAfterEdit = await api('GET', 'balances');
  check('editing the item list does not auto-complete', balancesAfterEdit.body.balances[uid] ?? 0, totalBalance);

  const completionsBefore = await api('GET', 'completions');
  const forChoreBefore = completionsBefore.body.completions.filter(
    (c) => c.choreId === choreId && c.scheduledDate === date
  );
  check('no completion recorded merely from editing', forChoreBefore.length, 0);

  const explicit = await completeChecklist(choreId, date);
  check('explicit complete succeeds once the edited list is satisfied', explicit.body.completed, true);
  totalBalance += 8;

  const balancesAfter = await api('GET', 'balances');
  check('balance credited by the explicit complete action', balancesAfter.body.balances[uid], totalBalance);
}

console.log('\n10. editing items does not retroactively change a past day');
{
  // A past day that already completed stays completed and byte-unchanged,
  // regardless of a later edit.
  const { choreId, items } = await makeChecklistChore(['Alpha', 'Beta', 'Gamma'], 11);
  const pastDate = '2026-07-01';

  await checkItem(choreId, items[0].id, pastDate);
  await checkItem(choreId, items[1].id, pastDate);
  const closing = await checkItem(choreId, items[2].id, pastDate);
  check('checklist completes on the past date', closing.body.completed, true);
  totalBalance += 11;

  const completionsBefore = await api('GET', 'completions');
  const forChoreBefore = completionsBefore.body.completions.filter(
    (c) => c.choreId === choreId && c.scheduledDate === pastDate
  );
  check('completion recorded for the past date', forChoreBefore.length, 1);

  const choreGet = await api('GET', 'chores');
  const chore = choreGet.body.chores.find((c) => c.id === choreId);
  await api('PUT', `chores/${choreId}`, { ...chore, items: [items[0]] });

  const completionsAfter = await api('GET', 'completions');
  const forChoreAfter = completionsAfter.body.completions.filter(
    (c) => c.choreId === choreId && c.scheduledDate === pastDate
  );
  check('the past day still shows exactly one completion after the edit', forChoreAfter.length, 1);
  check('the past completion is byte-unchanged by the edit', forChoreAfter[0], forChoreBefore[0]);

  const balances = await api('GET', 'balances');
  check('balance unaffected by editing items after the fact', balances.body.balances[uid], totalBalance);
}
{
  // A past day left incomplete stays incomplete, even if a later edit
  // would have made the (still) checked items satisfy the new list.
  const { choreId, items } = await makeChecklistChore(['Delta', 'Epsilon'], 6);
  const pastDate = '2026-07-02';

  await checkItem(choreId, items[0].id, pastDate);
  // items[1] deliberately left unchecked -- this day is never completed.

  const choreGet = await api('GET', 'chores');
  const chore = choreGet.body.chores.find((c) => c.id === choreId);
  // Now the checked items already cover what's required -- but nothing
  // ever re-evaluates a past day on its own, only a fresh check/uncheck/
  // complete call would, and none happens here.
  await api('PUT', `chores/${choreId}`, { ...chore, items: [items[0]] });

  const completions = await api('GET', 'completions');
  const forChore = completions.body.completions.filter(
    (c) => c.choreId === choreId && c.scheduledDate === pastDate
  );
  check('the past incomplete day is still not completed after the edit', forChore.length, 0);

  const balances = await api('GET', 'balances');
  check('balance unaffected -- nothing was credited', balances.body.balances[uid], totalBalance);
}

console.log('\n11. regression: a chore with no items still uses the single-tap flow unaffected');
{
  const res = await api('POST', 'chores', {
    title: 'Plain chore', icon: 'trash.fill', points: 3,
    recurrence: 'daily', weeklyDays: [], assignedToUID: uid, isActive: true,
  });
  const choreId = res.body.chore.id;
  check('chore created with no items', res.body.chore.items, []);

  const date = '2026-08-11';
  const completion = await api('POST', 'completions', {
    choreId, choreTitle: 'Plain chore', pointsAwarded: 3,
    completedByUID: uid, completedByName: 'Tester', scheduledDate: date,
  });
  check('plain completion still succeeds', completion.status, 201);
  totalBalance += 3;

  const balances = await api('GET', 'balances');
  check('plain chore credits normally', balances.body.balances[uid], totalBalance);

  const checkAttempt = await checkItem(choreId, 'nonexistent-item', date);
  check('checking an item on a non-checklist chore is refused', checkAttempt.status, 400);
}

console.log('\n12. cascade delete removes checklist progress');
{
  const queryChecklistItems = () =>
    ddb.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
        ExpressionAttributeValues: { ':pk': `HOUSEHOLD#${householdId}`, ':prefix': 'CHECKLIST#' },
      })
    );

  const before = await queryChecklistItems();
  check('checklist progress rows exist before account deletion', (before.Items ?? []).length > 0, true);

  const del = await api('DELETE', 'account');
  check('account deleted', del.status, 204);

  const after = await queryChecklistItems();
  check('checklist progress rows are gone after cascade delete', (after.Items ?? []).length, 0);
}

console.log(failures === 0 ? '\nCHECKLIST COMPLETION OK' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
