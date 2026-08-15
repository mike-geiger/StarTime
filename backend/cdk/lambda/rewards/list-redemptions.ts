import type { APIGatewayProxyHandler } from 'aws-lambda';
import { callerUid, callerHouseholdId } from '../common/auth';
import { json, errorResponse } from '../common/http';
import { queryRedemptions, presentRedemption } from './redemptions';

/**
 * The one place a missing fulfillment state gets its default (see
 * presentRedemption). Normalizing on read rather than backfilling the table
 * means no client ever has to know that status-less rows exist, and no
 * mutating script has to run against real family data.
 */
export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    const householdId = await callerHouseholdId(callerUid(event));
    const items = await queryRedemptions(householdId);
    return json(200, { redemptions: items.map(presentRedemption) });
  } catch (error) {
    return errorResponse(error);
  }
};
