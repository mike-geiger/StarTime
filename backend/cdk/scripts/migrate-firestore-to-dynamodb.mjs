#!/usr/bin/env node
/**
 * One-time Firestore -> DynamoDB migration for the Phase 6 cutover.
 *
 * Safety properties, in order of importance:
 *   - **Never writes to Firestore.** Every Firestore call here is a read. The
 *     old data stays intact as the rollback path.
 *   - **Idempotent.** Every item's PK/SK is derived deterministically from the
 *     source document, so re-running overwrites rather than duplicating. Safe
 *     to rehearse repeatedly and safe to re-run at cutover for a fresh copy.
 *   - **Dry-run by default.** Pass --write to actually write.
 *
 * IDs are preserved verbatim: Firestore document IDs become DynamoDB key
 * components, and Firebase UIDs stay as-is so they match the
 * `custom:legacy_uid` the migrate-user Lambda assigns on first sign-in.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=~/.config/startime/firebase-admin.json
 *   node scripts/migrate-firestore-to-dynamodb.mjs --table startime-prod            # dry run
 *   node scripts/migrate-firestore-to-dynamodb.mjs --table startime-prod --write
 */
import { cert, initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, BatchWriteCommand } from '@aws-sdk/lib-dynamodb';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const value = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const TABLE = value('--table');
const WRITE = flag('--write');
const REGION = value('--region', process.env.AWS_REGION ?? 'us-west-2');

if (!TABLE) {
  console.error('Usage: migrate-firestore-to-dynamodb.mjs --table <name> [--write] [--region <r>]');
  process.exit(1);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('GOOGLE_APPLICATION_CREDENTIALS must point at the Firebase service-account key.');
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });
const db = getFirestore();
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

/**
 * Firestore Timestamp | Date | undefined -> ISO string, or undefined when
 * the source has no timestamp (`users/{uid}` docs have no createdAt, and
 * writing a fake 1970 date would be worse than omitting the field --
 * removeUndefinedValues drops it).
 */
const isoOrNothing = (ts) => {
  if (!ts) return undefined;
  if (typeof ts.toDate === 'function') return ts.toDate().toISOString();
  if (ts instanceof Date) return ts.toISOString();
  return undefined;
};

/**
 * For the timestamps that are structurally required: completion and
 * redemption sort keys are built from them, so a missing one has to become
 * *something* stable rather than break the key. Epoch sorts oldest, which is
 * the least surprising place for an undated record to land.
 */
const isoRequired = (ts) => isoOrNothing(ts) ?? new Date(0).toISOString();

const items = [];
const stats = {};
const add = (kind, item) => {
  items.push(item);
  stats[kind] = (stats[kind] ?? 0) + 1;
};

console.log(`Reading Firestore (project: ${process.env.GOOGLE_CLOUD_PROJECT ?? 'from credentials'})...`);

// --- users/{uid} -------------------------------------------------------
for (const doc of (await db.collection('users').get()).docs) {
  const d = doc.data();
  add('profiles', {
    PK: `USER#${doc.id}`,
    SK: 'PROFILE',
    name: d.name,
    householdId: d.householdId ?? undefined,
    role: d.role ?? undefined,
    createdAt: isoOrNothing(d.createdAt),
  });
}

// --- households/{id} and subcollections --------------------------------
for (const householdDoc of (await db.collection('households').get()).docs) {
  const householdId = householdDoc.id;
  const h = householdDoc.data();

  add('households', {
    PK: `HOUSEHOLD#${householdId}`,
    SK: 'METADATA',
    id: householdId,
    name: h.name,
    members: h.members ?? {},
    lastJoinCode: h.lastJoinCode ?? undefined,
    createdAt: isoOrNothing(h.createdAt),
  });

  for (const c of (await householdDoc.ref.collection('chores').get()).docs) {
    const d = c.data();
    add('chores', {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `CHORE#${c.id}`,
      id: c.id,
      title: d.title,
      icon: d.icon,
      points: d.points,
      recurrence: d.recurrence,
      weeklyDays: d.weeklyDays ?? [],
      assignedToUID: d.assignedToUID,
      isActive: d.isActive ?? true,
      createdAt: isoOrNothing(d.createdAt),
    });
  }

  for (const r of (await householdDoc.ref.collection('rewards').get()).docs) {
    const d = r.data();
    add('rewards', {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `REWARD#${r.id}`,
      id: r.id,
      name: d.name,
      icon: d.icon,
      pointCost: d.pointCost,
      isActive: d.isActive ?? true,
      createdAt: isoOrNothing(d.createdAt),
    });
  }

  // Balances are recomputed from the ledger below rather than trusted from
  // anywhere, because Firestore never stored them -- the old app summed
  // these same two collections on the client (RewardStore.balance).
  const earned = {};
  const spent = {};

  for (const c of (await householdDoc.ref.collection('completions').get()).docs) {
    const d = c.data();
    const completedAt = isoRequired(d.completedAt);
    add('completions', {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `COMPLETION#${completedAt}#${c.id}`,
      id: c.id,
      choreId: d.choreId,
      choreTitle: d.choreTitle,
      pointsAwarded: d.pointsAwarded,
      completedByUID: d.completedByUID,
      completedByName: d.completedByName,
      completedAt,
      scheduledDate: d.scheduledDate,
    });
    earned[d.completedByUID] = (earned[d.completedByUID] ?? 0) + (d.pointsAwarded ?? 0);
  }

  for (const r of (await householdDoc.ref.collection('redemptions').get()).docs) {
    const d = r.data();
    const redeemedAt = isoRequired(d.redeemedAt);
    add('redemptions', {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `REDEMPTION#${redeemedAt}#${r.id}`,
      id: r.id,
      rewardId: d.rewardId,
      rewardName: d.rewardName,
      pointsSpent: d.pointsSpent,
      redeemedByUID: d.redeemedByUID,
      redeemedByName: d.redeemedByName,
      redeemedAt,
    });
    spent[d.redeemedByUID] = (spent[d.redeemedByUID] ?? 0) + (d.pointsSpent ?? 0);
  }

  // Exactly the old client-side formula: earned - spent, per uid.
  for (const uid of new Set([...Object.keys(earned), ...Object.keys(spent)])) {
    const balance = (earned[uid] ?? 0) - (spent[uid] ?? 0);
    add('balances', {
      PK: `HOUSEHOLD#${householdId}`,
      SK: `BALANCE#${uid}`,
      uid,
      balance,
    });
    console.log(`  balance ${householdId}/${uid}: earned ${earned[uid] ?? 0} - spent ${spent[uid] ?? 0} = ${balance}`);
  }
}

// --- inviteCodes/{code} ------------------------------------------------
for (const doc of (await db.collection('inviteCodes').get()).docs) {
  const d = doc.data();
  add('inviteCodes', {
    PK: `INVITECODE#${doc.id}`,
    SK: 'METADATA',
    householdId: d.householdId,
    role: d.role,
    createdByUID: d.createdByUID,
    createdAt: isoOrNothing(d.createdAt),
    // GSI1 is what the cascade-delete Lambda queries to find a household's
    // codes -- migrated rows need it just like newly created ones.
    GSI1PK: `HOUSEHOLD#${d.householdId}`,
    GSI1SK: `INVITECODE#${doc.id}`,
  });
}

console.log('\nSummary:');
for (const [kind, count] of Object.entries(stats)) console.log(`  ${kind}: ${count}`);
console.log(`  TOTAL ITEMS: ${items.length}`);

if (!WRITE) {
  console.log('\nDRY RUN -- nothing written. Sample items:');
  for (const item of items.slice(0, 3)) console.log('  ' + JSON.stringify(item));
  console.log('\nRe-run with --write to apply.');
  process.exit(0);
}

console.log(`\nWriting ${items.length} items to ${TABLE} in ${REGION}...`);
for (let i = 0; i < items.length; i += 25) {
  let requests = items.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } }));
  for (let attempt = 0; attempt < 5 && requests.length > 0; attempt++) {
    const result = await ddb.send(new BatchWriteCommand({ RequestItems: { [TABLE]: requests } }));
    const unprocessed = result.UnprocessedItems?.[TABLE] ?? [];
    if (unprocessed.length === 0) break;
    requests = unprocessed;
    await new Promise((r) => setTimeout(r, 50 * 2 ** attempt));
  }
  process.stdout.write(`\r  ${Math.min(i + 25, items.length)}/${items.length}`);
}

console.log('\nMIGRATION COMPLETE');
