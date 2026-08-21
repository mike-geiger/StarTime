import type { APIGatewayProxyHandler } from 'aws-lambda';
import { GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';
import { completeChecklistDay } from './common/complete-checklist-day';

/**
 * Checks one item on a checklist chore for a given day, and closes the day
 * out -- crediting points, exactly once -- if this is the item that
 * completes the set.
 *
 * Two writes, not one transaction: the item check itself is unconditional
 * and always succeeds; only the closing transaction (below) is guarded.
 * That split, plus a strongly consistent re-read after the item write
 * lands, is what makes two different "last items" checked at the same
 * moment resolve safely without a retry loop -- see design.md.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const choreId = event.pathParameters?.choreId;
    const itemId = event.pathParameters?.itemId;
    const scheduledDate = event.queryStringParameters?.scheduledDate;
    if (!choreId || !itemId || !scheduledDate) {
      throw new HttpError(400, 'choreId, itemId and scheduledDate are required');
    }

    const choreResult = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: Keys.chore(householdId, choreId) })
    );
    const chore = choreResult.Item;
    if (!chore) {
      throw new HttpError(404, 'That chore no longer exists.');
    }
    const items: { id: string; title: string }[] = chore.items ?? [];
    if (items.length === 0) {
      throw new HttpError(400, 'That chore has no checklist.');
    }
    if (!items.some((it) => it.id === itemId)) {
      throw new HttpError(400, 'That item is not on this checklist.');
    }

    // Unconditional and idempotent: a double-tap on the same item just
    // unions into the same set twice.
    await ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: Keys.checklistProgress(householdId, choreId, scheduledDate),
        UpdateExpression:
          'ADD checkedItemIds :item SET choreId = :choreId, scheduledDate = :scheduledDate',
        ExpressionAttributeValues: {
          ':item': new Set([itemId]),
          ':choreId': choreId,
          ':scheduledDate': scheduledDate,
        },
      })
    );

    // Strongly consistent: DynamoDB serializes writes to a single item, so
    // whichever of two concurrent "closing" checks lands second is
    // guaranteed to see the other's contribution here too.
    const progressResult = await ddb.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: Keys.checklistProgress(householdId, choreId, scheduledDate),
        ConsistentRead: true,
      })
    );
    const checkedItemIds: Set<string> = progressResult.Item?.checkedItemIds ?? new Set();
    const isComplete = items.every((it) => checkedItemIds.has(it.id));

    let completed = false;
    if (isComplete) {
      const outcome = await completeChecklistDay({
        householdId,
        chore: {
          id: choreId,
          title: chore.title,
          points: chore.points,
          assignedToUID: chore.assignedToUID,
        },
        scheduledDate,
      });
      completed = 'completion' in outcome;
    }

    return json(200, { checkedItemIds: [...checkedItemIds], completed });
  } catch (error) {
    return errorResponse(error);
  }
};
