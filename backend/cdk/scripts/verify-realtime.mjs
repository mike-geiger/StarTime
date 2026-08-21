#!/usr/bin/env node
/**
 * End-to-end check that a write reaches a connected client as a pushed
 * invalidation: sign up -> create household -> open WebSocket -> write a
 * chore over REST -> assert the socket receives {"type":"invalidate",...}.
 *
 * The XCUITest suite drives a single client and so can't observe push at
 * all; this exercises the authorizer, $connect, DynamoDB Streams, and the
 * fan-out Lambda together.
 *
 * Expects the env vars that with-ephemeral-stack.sh exports.
 */
import {
  CognitoIdentityProviderClient,
  SignUpCommand,
  InitiateAuthCommand,
} from '@aws-sdk/client-cognito-identity-provider';

const {
  STARTIME_USER_POOL_CLIENT_ID: CLIENT_ID,
  STARTIME_API_BASE_URL: API_URL,
  STARTIME_WEB_SOCKET_URL: WS_URL,
  AWS_REGION = 'us-west-2',
} = process.env;

if (!CLIENT_ID || !API_URL || !WS_URL) {
  console.error('Missing STARTIME_USER_POOL_CLIENT_ID / STARTIME_API_BASE_URL / STARTIME_WEB_SOCKET_URL');
  process.exit(1);
}

const cognito = new CognitoIdentityProviderClient({ region: AWS_REGION });
const email = `realtime-${Date.now()}@example.com`;
const password = 'TempPass123!';

const fail = (msg) => {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
};

console.log('1. signing up', email);
await cognito.send(new SignUpCommand({ ClientId: CLIENT_ID, Username: email, Password: password }));

const auth = await cognito.send(
  new InitiateAuthCommand({
    ClientId: CLIENT_ID,
    AuthFlow: 'USER_PASSWORD_AUTH',
    AuthParameters: { USERNAME: email, PASSWORD: password },
  })
);
const idToken = auth.AuthenticationResult?.IdToken;
if (!idToken) fail('no ID token');

const api = async (method, path, body) => {
  const res = await fetch(`${API_URL.replace(/\/$/, '')}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${idToken}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) fail(`${method} ${path} -> ${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
};

console.log('2. creating household');
await api('POST', 'households', { name: 'Realtime Test', displayName: 'Tester' });

console.log('3. opening WebSocket');
const ws = new WebSocket(`${WS_URL}?token=${encodeURIComponent(idToken)}`);

// A rejected handshake surfaces only as a generic 'error' event, so capture
// the close code/reason too -- 1006 usually means the authorizer denied,
// while a $connect failure closes with a server-side reason.
let closeInfo = null;
ws.addEventListener('close', (event) => {
  closeInfo = `code=${event.code} reason=${event.reason || '(none)'}`;
});

// Reusable per-wait: each call arms a fresh listener so this can be used
// more than once on the same socket (once per write under test).
function waitForInvalidation() {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('no invalidation within 30s')), 30_000);
    const onMessage = (event) => {
      cleanup();
      resolve(JSON.parse(event.data));
    };
    const onError = () => {
      cleanup();
      reject(new Error(`WebSocket error ${closeInfo ?? '(no close frame)'}`));
    };
    const cleanup = () => {
      clearTimeout(timer);
      ws.removeEventListener('message', onMessage);
      ws.removeEventListener('error', onError);
    };
    ws.addEventListener('message', onMessage);
    ws.addEventListener('error', onError);
  });
}

await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve);
  ws.addEventListener('error', () =>
    setTimeout(
      () => reject(new Error(`WebSocket failed to open ${closeInfo ?? '(no close frame)'}`)),
      50
    )
  );
  setTimeout(() => reject(new Error('WebSocket open timed out')), 15_000);
});
console.log('   connected');

console.log('4. writing a chore over REST');
const choreWritten = waitForInvalidation(); // armed before the write, not after
await api('POST', 'chores', {
  title: 'Realtime probe',
  icon: 'sparkles',
  points: 5,
  recurrence: 'daily',
  weeklyDays: [],
  assignedToUID: 'someone',
  isActive: true,
});

console.log('5. waiting for pushed invalidation...');
try {
  const message = await choreWritten;
  console.log('   received:', JSON.stringify(message));
  if (message.type !== 'invalidate' || !message.resources?.includes('chores')) {
    fail(`unexpected payload: ${JSON.stringify(message)}`);
  }
} catch (error) {
  fail(error.message);
}

// A checklist chore's progress lives under a CHECKLIST# sort key, not
// CHORE# or COMPLETION# -- stream-fanout.ts has to classify that prefix
// explicitly (as the "chores" resource) or this invalidation is silently
// dropped, and a second device's checkboxes would just never update.
console.log('6. checking a checklist item over REST (isolated: one item on a');
console.log('   two-item chore, so this write touches only CHECKLIST#, no');
console.log('   COMPLETION#/BALANCE# writes to muddy which prefix triggered it)');
const checklistChore = await api('POST', 'chores', {
  title: 'Checklist realtime probe',
  icon: 'sparkles',
  points: 5,
  recurrence: 'daily',
  weeklyDays: [],
  assignedToUID: 'someone',
  isActive: true,
  items: [
    { id: 'a', title: 'First' },
    { id: 'b', title: 'Second' },
  ],
});
const checklistChoreId = checklistChore.chore.id;

const itemChecked = waitForInvalidation();
await api('POST', `chores/${checklistChoreId}/checklist/items/a/check?scheduledDate=2026-08-05`);

try {
  const message = await itemChecked;
  console.log('   received:', JSON.stringify(message));
  if (message.type !== 'invalidate' || !message.resources?.includes('chores')) {
    fail(`unexpected payload: ${JSON.stringify(message)}`);
  }
} catch (error) {
  fail(error.message);
}

console.log('REALTIME OK');
ws.close();
process.exit(0);
