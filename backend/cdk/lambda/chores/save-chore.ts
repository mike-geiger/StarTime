import type { APIGatewayProxyHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import { PutCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME, Keys } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

/**
 * Handles both create (POST, no id) and update (PUT, id in the path). The
 * Firestore original used `setData(from:)` for both -- a whole-document
 * overwrite either way -- so a single handler keeps that behavior rather
 * than inventing a partial-update path the client never uses.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const body = JSON.parse(event.body ?? '{}');
    const choreId = event.pathParameters?.choreId ?? randomUUID();

    const { title, icon, points, recurrence, weeklyDays, assignedToUID, isActive, items } = body;
    if (!title || !icon || typeof points !== 'number' || !recurrence || !assignedToUID) {
      throw new HttpError(400, 'title, icon, points, recurrence and assignedToUID are required');
    }

    // Checklist items are optional and, when present, gate this chore's
    // completion (see check-checklist-item.ts) instead of a single tap.
    // Ids are generated client-side -- there's no per-item endpoint, items
    // travel through this whole-object overwrite -- so this only validates
    // shape, never assigns ids of its own.
    const choreItems: { id: string; title: string }[] = [];
    if (items !== undefined) {
      if (!Array.isArray(items)) {
        throw new HttpError(400, 'items must be an array');
      }
      const seenIds = new Set<string>();
      for (const entry of items) {
        if (
          !entry ||
          typeof entry.id !== 'string' ||
          !entry.id ||
          typeof entry.title !== 'string' ||
          !entry.title
        ) {
          throw new HttpError(400, 'each checklist item requires a non-empty id and title');
        }
        if (seenIds.has(entry.id)) {
          throw new HttpError(400, 'checklist item ids must be unique');
        }
        seenIds.add(entry.id);
        choreItems.push({ id: entry.id, title: entry.title });
      }
    }

    const item = {
      ...Keys.chore(householdId, choreId),
      id: choreId,
      title,
      icon,
      points,
      recurrence,
      weeklyDays: weeklyDays ?? [],
      assignedToUID,
      isActive: isActive ?? true,
      items: choreItems,
      createdAt: body.createdAt ?? new Date().toISOString(),
    };

    await ddb.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));

    const { PK, SK, ...chore } = item;
    return json(event.pathParameters?.choreId ? 200 : 201, { chore });
  } catch (error) {
    return errorResponse(error);
  }
};
