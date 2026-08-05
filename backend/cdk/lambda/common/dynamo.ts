import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
export const ddb = DynamoDBDocumentClient.from(client, {
  marshallOptions: { removeUndefinedValues: true },
});

export const TABLE_NAME = process.env.TABLE_NAME!;

/** Key builders for every item shape in the single-table design (see data-stack.ts). */
export const Keys = {
  household: (id: string) => ({ PK: `HOUSEHOLD#${id}`, SK: 'METADATA' }),
  userProfile: (uid: string) => ({ PK: `USER#${uid}`, SK: 'PROFILE' }),
  inviteCode: (code: string) => ({ PK: `INVITECODE#${code}`, SK: 'METADATA' }),
  chore: (householdId: string, choreId: string) => ({ PK: `HOUSEHOLD#${householdId}`, SK: `CHORE#${choreId}` }),
  reward: (householdId: string, rewardId: string) => ({ PK: `HOUSEHOLD#${householdId}`, SK: `REWARD#${rewardId}` }),
  balance: (householdId: string, uid: string) => ({ PK: `HOUSEHOLD#${householdId}`, SK: `BALANCE#${uid}` }),
  /**
   * Enforces one completion per chore per day (see record-completion.ts).
   *
   * "COMPLETEDON#" deliberately sorts *before* "COMPLETION#" ('E' < 'I' at
   * the 8th character), so these markers fall outside the
   * `SK BETWEEN 'COMPLETION#...' AND 'COMPLETION#~'` range the completion
   * queries use and never leak into results.
   */
  completionMarker: (householdId: string, choreId: string, scheduledDate: string) => ({
    PK: `HOUSEHOLD#${householdId}`,
    SK: `COMPLETEDON#${choreId}#${scheduledDate}`,
  }),
};
