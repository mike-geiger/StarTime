#!/usr/bin/env node
/**
 * Exercises the redemption fulfillment lifecycle end to end, against the
 * real API with two real identities.
 *
 * The XCUITest suite drives a single client, so it structurally cannot check
 * the two things that matter most here: that a *child's* token is refused on
 * every transition, and that concurrent cancellations refund exactly once.
 * A read-then-write guard passes the sequential case and fails the
 * concurrent one -- the same shape of bug that once double-credited a chore.
 *
 * Covers: pending on redeem with an immediate debit, fulfil, un-fulfil,
 * cancel-with-refund, every illegal transition, parent-only authorization,
 * concurrent cancels, and the status-less legacy row default.
 *
 * Expects the env vars with-ephemeral-stack.sh exports.
 */
import {
  CognitoIdentityProviderClient,
  SignUpCommand,
  InitiateAuthCommand,
} from '@aws-sdk/client-cognito-identity-provider';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';

const {
  STARTIME_USER_POOL_CLIENT_ID: CLIENT_ID,
  STARTIME_API_BASE_URL: API_URL,
  STARTIME_TABLE_NAME: TABLE,
  AWS_REGION = 'us-west-2',
} = process.env;

if (!CLIENT_ID || !API_URL || !TABLE) {
  console.error(
    'Missing STARTIME_USER_POOL_CLIENT_ID / STARTIME_API_BASE_URL / STARTIME_TABLE_NAME'
  );
  process.exit(1);
}

const cognito = new CognitoIdentityProviderClient({ region: AWS_REGION });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: AWS_REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

let failures = 0;
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(
    `  ${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : ` -- got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`}`
  );
  if (!ok) failures++;
};

const password = 'TempPass123!';
const stamp = Date.now();

async function signUp(label) {
  const email = `redemption-${label}-${stamp}@example.com`;
  await cognito.send(new SignUpCommand({ ClientId: CLIENT_ID, Username: email, Password: password }));
  const auth = await cognito.send(
    new InitiateAuthCommand({
      ClientId: CLIENT_ID,
      AuthFlow: 'USER_PASSWORD_AUTH',
      AuthParameters: { USERNAME: email, PASSWORD: password },
    })
  );
  const idToken = auth.AuthenticationResult.IdToken;
  const uid = JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString())[
    'custom:legacy_uid'
  ];
  const call = async (method, path, body) => {
    const res = await fetch(`${API_URL.replace(/\/$/, '')}/${path}`, {
      method,
      headers: { Authorization: `Bearer ${idToken}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: res.status === 204 ? null : await res.json() };
  };
  return { email, idToken, uid, api: call };
}

const parent = await signUp('parent');
const child = await signUp('child');

// Both accounts get deleted whatever happens -- an ephemeral stack is torn
// down anyway, but a leaked account here would also leak a household when
// this script is pointed at a longer-lived stage.
async function cleanup() {
  console.log('cleanup: deleting accounts');
  for (const [label, who] of [
    ['child', child],
    ['parent', parent],
  ]) {
    try {
      const del = await who.api('DELETE', 'account');
      console.log(`  ${label} account -> ${del.status}`);
    } catch (error) {
      console.error(`  ${label} account cleanup failed:`, error.message);
    }
  }
}

let householdId;

try {
  console.log('1. parent creates a household, child joins as a child');
  const created = await parent.api('POST', 'households', {
    name: 'Lifecycle',
    displayName: 'Parent',
  });
  check('household created', created.status, 201);
  householdId = created.body.household.id;

  const invite = await parent.api('POST', 'households/invite-codes', { role: 'child' });
  check('invite code created', invite.status, 201);

  const joined = await child.api('POST', 'households/join', {
    code: invite.body.code,
    displayName: 'Kiddo',
  });
  check('child joined', joined.status, 200);

  console.log('2. child earns points');
  const chore = await parent.api('POST', 'chores', {
    title: 'Make bed',
    icon: 'bed.double.fill',
    points: 30,
    recurrence: 'daily',
    weeklyDays: [],
    assignedToUID: child.uid,
    isActive: true,
  });
  const choreId = chore.body.chore.id;
  await child.api('POST', 'completions', {
    choreId,
    choreTitle: 'Make bed',
    pointsAwarded: 30,
    completedByUID: child.uid,
    completedByName: 'Kiddo',
    scheduledDate: '2026-08-05',
  });
  const earned = await parent.api('GET', 'balances');
  check('child earned 30', earned.body.balances[child.uid], 30);

  const reward = await parent.api('POST', 'rewards', {
    name: 'Ice cream',
    icon: 'gift.fill',
    pointCost: 10,
    isActive: true,
  });
  const rewardId = reward.body.reward.id;

  const redeem = async () =>
    child.api('POST', 'redemptions', {
      rewardId,
      redeemedByUID: child.uid,
      redeemedByName: 'Kiddo',
    });
  const patch = (who, id, status) => who.api('PATCH', `redemptions/${id}`, { status });
  const balanceOf = async (uid) => (await parent.api('GET', 'balances')).body.balances[uid];
  const redemptionById = async (id) => {
    const all = await parent.api('GET', 'redemptions');
    return all.body.redemptions.find((r) => r.id === id);
  };

  console.log('3. redeeming leaves it pending and debits immediately');
  const first = await redeem();
  check('redeem accepted', first.status, 201);
  const firstId = first.body.redemption.id;
  check('new redemption is pending', first.body.redemption.status, 'pending');
  check('points debited at redeem time', await balanceOf(child.uid), 20);

  console.log('4. parent fulfils, then un-fulfils; neither moves points');
  const fulfilled = await patch(parent, firstId, 'fulfilled');
  check('fulfil accepted', fulfilled.status, 200);
  check('now fulfilled', fulfilled.body.redemption.status, 'fulfilled');
  check('records the resolving parent', fulfilled.body.redemption.fulfilledByUID, parent.uid);
  check('balance unchanged by fulfil', await balanceOf(child.uid), 20);

  const unfulfilled = await patch(parent, firstId, 'pending');
  check('un-fulfil accepted', unfulfilled.status, 200);
  check('back to pending', unfulfilled.body.redemption.status, 'pending');
  check('fulfilledByUID cleared', unfulfilled.body.redemption.fulfilledByUID, undefined);
  check('balance unchanged by un-fulfil', await balanceOf(child.uid), 20);

  console.log('5. cancelling returns exactly the points that were spent');
  // Reprice the reward first: the refund must follow the ledger entry, not
  // whatever the reward costs now.
  await parent.api('PUT', `rewards/${rewardId}`, {
    id: rewardId,
    name: 'Ice cream',
    icon: 'gift.fill',
    pointCost: 99,
    isActive: true,
  });
  const cancelled = await patch(parent, firstId, 'cancelled');
  check('cancel accepted', cancelled.status, 200);
  check('now cancelled', cancelled.body.redemption.status, 'cancelled');
  check('refund is the points originally spent', await balanceOf(child.uid), 30);
  check('entry still in the ledger', (await redemptionById(firstId))?.status, 'cancelled');
  check('points spent unchanged', (await redemptionById(firstId))?.pointsSpent, 10);

  // Put the price back so the remaining cases are readable.
  await parent.api('PUT', `rewards/${rewardId}`, {
    id: rewardId,
    name: 'Ice cream',
    icon: 'gift.fill',
    pointCost: 10,
    isActive: true,
  });

  console.log('6. illegal transitions are refused');
  check('cancelled cannot be fulfilled', (await patch(parent, firstId, 'fulfilled')).status, 409);
  check('cancelled cannot be un-fulfilled', (await patch(parent, firstId, 'pending')).status, 409);
  check('cancelled cannot be re-cancelled', (await patch(parent, firstId, 'cancelled')).status, 409);
  check('balance untouched by refusals', await balanceOf(child.uid), 30);

  const second = await redeem();
  const secondId = second.body.redemption.id;
  await patch(parent, secondId, 'fulfilled');
  const cancelFulfilled = await patch(parent, secondId, 'cancelled');
  check('fulfilled cannot be cancelled directly', cancelFulfilled.status, 409);
  check('and says to un-fulfil first', /unfulfilled first/i.test(cancelFulfilled.body.message), true);
  check('no refund from a refused cancel', await balanceOf(child.uid), 20);

  check('unknown redemption id is 404', (await patch(parent, 'no-such-id', 'fulfilled')).status, 404);
  check('an invalid target state is 400', (await patch(parent, secondId, 'shipped')).status, 400);

  console.log('7. a child cannot resolve anything, including their own');
  const third = await redeem();
  const thirdId = third.body.redemption.id;
  for (const status of ['fulfilled', 'pending', 'cancelled']) {
    check(`child -> ${status} is 403`, (await patch(child, thirdId, status)).status, 403);
  }
  check('their redemption is untouched', (await redemptionById(thirdId))?.status, 'pending');
  check('and no points moved', await balanceOf(child.uid), 10);

  console.log('8. five concurrent cancels refund exactly once');
  const races = await Promise.all([1, 2, 3, 4, 5].map(() => patch(parent, thirdId, 'cancelled')));
  const statuses = races.map((r) => r.status).sort();
  console.log('   statuses:', statuses.join(', '));
  check('exactly one 200', statuses.filter((s) => s === 200).length, 1);
  check('rest are 409', statuses.filter((s) => s === 409).length, 4);
  check('refunded once, not five times', await balanceOf(child.uid), 20);

  console.log('9. a status-less legacy row reads as fulfilled');
  const legacyId = 'legacy-redemption-id';
  const legacyAt = '2026-07-02T12:00:00.000Z';
  await ddb.send(
    new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `HOUSEHOLD#${householdId}`,
        SK: `REDEMPTION#${legacyAt}#${legacyId}`,
        id: legacyId,
        rewardId,
        rewardName: 'Ice cream',
        pointsSpent: 10,
        redeemedByUID: child.uid,
        redeemedByName: 'Kiddo',
        redeemedAt: legacyAt,
        // deliberately no `status` -- this is the pre-lifecycle shape
      },
    })
  );
  check('legacy row reads as fulfilled', (await redemptionById(legacyId))?.status, 'fulfilled');
  check(
    'so it is not in the pending queue',
    (await parent.api('GET', 'redemptions')).body.redemptions
      .filter((r) => r.status === 'pending')
      .map((r) => r.id),
    []
  );
  const legacyUnfulfil = await patch(parent, legacyId, 'pending');
  check('a legacy row can still be un-fulfilled', legacyUnfulfil.status, 200);
  check('and becomes pending', legacyUnfulfil.body.redemption.status, 'pending');
  check('un-fulfilling it moved no points', await balanceOf(child.uid), 20);
} finally {
  await cleanup();
}

console.log(failures === 0 ? '\nREDEMPTION LIFECYCLE OK' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
