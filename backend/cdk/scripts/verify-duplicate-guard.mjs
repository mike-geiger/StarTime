#!/usr/bin/env node
/**
 * Proves the once-per-chore-per-day guard in record-completion.ts holds
 * under the exact condition the client-side check can't: two requests racing.
 *
 * Fires N completions for the same chore and scheduledDate simultaneously and
 * asserts exactly one wins, the rest get 409, and the balance reflects a
 * single award. A client-only guard passes the sequential case and fails this
 * one -- which is how a double-tap double-credited points in prod.
 */
import {
  CognitoIdentityProviderClient,
  SignUpCommand,
  InitiateAuthCommand,
} from '@aws-sdk/client-cognito-identity-provider';

const {
  STARTIME_USER_POOL_CLIENT_ID: CLIENT_ID,
  STARTIME_API_BASE_URL: API_URL,
  AWS_REGION = 'us-west-2',
} = process.env;

if (!CLIENT_ID || !API_URL) {
  console.error('Missing STARTIME_USER_POOL_CLIENT_ID / STARTIME_API_BASE_URL');
  process.exit(1);
}

let failures = 0;
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : ` -- got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`}`);
  if (!ok) failures++;
};

const cognito = new CognitoIdentityProviderClient({ region: AWS_REGION });
const email = `dupguard-${Date.now()}@example.com`;
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

console.log('2. creating household + chore');
await api('POST', 'households', { name: 'Dup Guard', displayName: 'Tester' });
const chore = await api('POST', 'chores', {
  title: 'Make bed', icon: 'bed.double.fill', points: 5,
  recurrence: 'daily', weeklyDays: [], assignedToUID: uid, isActive: true,
});
const choreId = chore.body.chore.id;

const scheduledDate = '2026-08-05';
const payload = {
  choreId, choreTitle: 'Make bed', pointsAwarded: 5,
  completedByUID: uid, completedByName: 'Tester', scheduledDate,
};

console.log('3. firing 5 identical completions concurrently');
const results = await Promise.all([1, 2, 3, 4, 5].map(() => api('POST', 'completions', payload)));
const statuses = results.map((r) => r.status).sort();
console.log('   statuses:', statuses.join(', '));

check('exactly one 201', statuses.filter((s) => s === 201).length, 1);
check('rest are 409', statuses.filter((s) => s === 409).length, 4);

console.log('4. verifying ledger and balance');
const completions = await api('GET', 'completions');
check('one completion stored', completions.body.completions.length, 1);

const balances = await api('GET', 'balances');
check('balance credited once', balances.body.balances[uid], 5);

console.log('5. a different day is still allowed');
const nextDay = await api('POST', 'completions', { ...payload, scheduledDate: '2026-08-06' });
check('next-day completion accepted', nextDay.status, 201);
const after = await api('GET', 'balances');
check('balance now 10', after.body.balances[uid], 10);

console.log('6. cleanup');
const del = await api('DELETE', 'account');
check('account deleted', del.status, 204);

console.log(failures === 0 ? '\nDUPLICATE GUARD OK' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
