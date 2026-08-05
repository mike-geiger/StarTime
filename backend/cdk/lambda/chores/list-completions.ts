import type { APIGatewayProxyHandler } from 'aws-lambda';
import { QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME } from '../common/dynamo';
import { callerUid, callerHouseholdId } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const since = event.queryStringParameters?.since;

    // `SK BETWEEN` rather than a bare `SK > :since`: without an upper bound,
    // the range would also sweep up METADATA/REDEMPTION#/REWARD# items that
    // sort after "COMPLETION#" under the same PK. "~" (0x7E) is above every
    // character that can appear in a timestamp or uuid.
    const lower = since ? `COMPLETION#${since}` : 'COMPLETION#';
    const items = [];
    let lastEvaluatedKey: Record<string, unknown> | undefined;

    do {
      const result = await ddb.send(
        new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND SK BETWEEN :lo AND :hi',
          ExpressionAttributeValues: {
            ':pk': `HOUSEHOLD#${householdId}`,
            ':lo': lower,
            ':hi': 'COMPLETION#~',
          },
          ExclusiveStartKey: lastEvaluatedKey,
        })
      );
      items.push(...(result.Items ?? []));
      lastEvaluatedKey = result.LastEvaluatedKey;
    } while (lastEvaluatedKey);

    return json(200, { completions: items });
  } catch (error) {
    return errorResponse(error);
  }
};
