import { randomUUID } from 'node:crypto';
import { GetCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../../common/dynamo';

interface ChoreForCompletion {
  id: string;
  title: string;
  points: number;
  assignedToUID: string;
}

/**
 * Runs the same closing transaction `record-completion.ts` performs for a
 * single-tap chore -- Put ChoreCompletion + ADD balance + Put COMPLETEDON#
 * marker under attribute_not_exists(PK) -- for a checklist chore. Sourced
 * from the chore record itself rather than a client-supplied completion
 * body: this fires as a side effect of checking the item that closes the
 * set, or from the explicit "mark complete" action, neither of which
 * carries one.
 *
 * Returns `{ alreadyComplete: true }` rather than throwing when the
 * marker's condition fails -- a concurrent request already closed this
 * day, which is success from the caller's point of view, not an error.
 */
export async function completeChecklistDay(params: {
  householdId: string;
  chore: ChoreForCompletion;
  scheduledDate: string;
}): Promise<{ completion: Record<string, unknown> } | { alreadyComplete: true }> {
  const { householdId, chore, scheduledDate } = params;

  const householdResult = await ddb.send(
    new GetCommand({ TableName: TABLE_NAME, Key: Keys.household(householdId) })
  );
  const completedByName: string = householdResult.Item?.members?.[chore.assignedToUID]?.name ?? '';

  const id = randomUUID();
  const completedAt = new Date().toISOString();
  const completion = {
    PK: `HOUSEHOLD#${householdId}`,
    SK: `COMPLETION#${completedAt}#${id}`,
    id,
    choreId: chore.id,
    choreTitle: chore.title,
    pointsAwarded: chore.points,
    completedByUID: chore.assignedToUID,
    completedByName,
    completedAt,
    scheduledDate,
  };

  try {
    await ddb.send(
      new TransactWriteCommand({
        TransactItems: [
          { Put: { TableName: TABLE_NAME, Item: completion } },
          {
            Update: {
              TableName: TABLE_NAME,
              Key: Keys.balance(householdId, chore.assignedToUID),
              UpdateExpression: 'ADD #balance :points SET #uid = :uid',
              ExpressionAttributeNames: { '#balance': 'balance', '#uid': 'uid' },
              ExpressionAttributeValues: { ':points': chore.points, ':uid': chore.assignedToUID },
            },
          },
          {
            Put: {
              TableName: TABLE_NAME,
              Item: {
                ...Keys.completionMarker(householdId, chore.id, scheduledDate),
                choreId: chore.id,
                scheduledDate,
                completionId: id,
                completedAt,
              },
              ConditionExpression: 'attribute_not_exists(PK)',
            },
          },
        ],
      })
    );
  } catch (error) {
    if (error instanceof Error && error.name === 'TransactionCanceledException') {
      return { alreadyComplete: true };
    }
    throw error;
  }

  const { PK, SK, ...body } = completion;
  return { completion: body };
}
