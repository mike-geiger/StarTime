import type { APIGatewayProxyHandler } from 'aws-lambda';
import { QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME } from '../common/dynamo';
import { callerUid, callerHouseholdId, HttpError } from '../common/auth';
import { json, errorResponse } from '../common/http';

/**
 * A household's checklist progress for one day -- which items are checked
 * so far on each checklist chore. Needed so a fresh app launch, or a
 * second device, can render checkboxes reflecting what's already checked;
 * check/uncheck only return their own delta, not the whole picture.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const scheduledDate = event.queryStringParameters?.scheduledDate;
    if (!scheduledDate) {
      throw new HttpError(400, 'scheduledDate is required');
    }

    // CHECKLIST# items for every chore share the same prefix regardless of
    // day, so the day itself has to be a filter, not part of the key
    // condition -- same shape as list-chores.ts's isActive filter.
    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
        FilterExpression: 'scheduledDate = :date',
        ExpressionAttributeValues: {
          ':pk': `HOUSEHOLD#${householdId}`,
          ':prefix': 'CHECKLIST#',
          ':date': scheduledDate,
        },
      })
    );

    // checkedItemIds is a DynamoDB String Set, which unmarshals to a JS
    // Set -- JSON.stringify would silently emit "{}" for one, so it has to
    // be spread into an array before this goes out over the wire.
    const checklists = (result.Items ?? []).map((item) => ({
      choreId: item.choreId,
      scheduledDate: item.scheduledDate,
      checkedItemIds: [...(item.checkedItemIds ?? [])],
    }));

    return json(200, { checklists });
  } catch (error) {
    return errorResponse(error);
  }
};
