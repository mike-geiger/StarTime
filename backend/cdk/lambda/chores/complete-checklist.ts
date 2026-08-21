import type { APIGatewayProxyHandler } from 'aws-lambda';
import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';
import { completeChecklistDay } from './common/complete-checklist-day';

/**
 * Explicitly completes a checklist chore for a day whose checked items
 * already satisfy every currently-required item, without a new item check
 * to trigger it -- the case where editing the item list (removing one)
 * left an already-checked set covering what's left required. Completion
 * only ever comes from a deliberate action, never as a side effect of an
 * edit, so this action exists rather than auto-completing on the edit.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const choreId = event.pathParameters?.choreId;
    const scheduledDate = event.queryStringParameters?.scheduledDate;
    if (!choreId || !scheduledDate) {
      throw new HttpError(400, 'choreId and scheduledDate are required');
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

    const progressResult = await ddb.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: Keys.checklistProgress(householdId, choreId, scheduledDate),
        ConsistentRead: true,
      })
    );
    const checkedItemIds: Set<string> = progressResult.Item?.checkedItemIds ?? new Set();
    const isComplete = items.every((it) => checkedItemIds.has(it.id));
    if (!isComplete) {
      throw new HttpError(409, 'Not every item is checked yet.');
    }

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

    return json(200, { completed: 'completion' in outcome });
  } catch (error) {
    return errorResponse(error);
  }
};
