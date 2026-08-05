import type { APIGatewayProxyHandler } from 'aws-lambda';
import { QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ddb, TABLE_NAME } from '../common/dynamo';
import { callerUid, callerHouseholdId } from '../common/auth';
import { json, errorResponse } from '../common/http';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));

    const items = [];
    let lastEvaluatedKey: Record<string, unknown> | undefined;

    do {
      const result = await ddb.send(
        new QueryCommand({
          TableName: TABLE_NAME,
          // See list-completions.ts for why this needs an explicit upper bound.
          KeyConditionExpression: 'PK = :pk AND SK BETWEEN :lo AND :hi',
          ExpressionAttributeValues: {
            ':pk': `HOUSEHOLD#${householdId}`,
            ':lo': 'REDEMPTION#',
            ':hi': 'REDEMPTION#~',
          },
          ExclusiveStartKey: lastEvaluatedKey,
        })
      );
      items.push(...(result.Items ?? []));
      lastEvaluatedKey = result.LastEvaluatedKey;
    } while (lastEvaluatedKey);

    return json(200, { redemptions: items });
  } catch (error) {
    return errorResponse(error);
  }
};
