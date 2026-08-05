import type { PostConfirmationTriggerHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import {
  AdminUpdateUserAttributesCommand,
  CognitoIdentityProviderClient,
} from '@aws-sdk/client-cognito-identity-provider';

const client = new CognitoIdentityProviderClient({});

// Stamps a canonical app-level user id into every fresh sign-up, mirroring
// what the migrate-user trigger does for accounts carried over from Firebase
// (see migrate-user.ts) so every Lambda can key off one consistent claim
// (custom:legacy_uid) regardless of which path created the account.
//
// PostConfirmation_ConfirmSignUp only fires for the normal sign-up flow --
// the UserMigration trigger's silent account creation during sign-in does
// not trigger PostConfirmation, so this never overwrites a migrated uid.
export const handler: PostConfirmationTriggerHandler = async (event) => {
  if (event.triggerSource !== 'PostConfirmation_ConfirmSignUp') {
    return event;
  }

  await client.send(
    new AdminUpdateUserAttributesCommand({
      UserPoolId: event.userPoolId,
      Username: event.userName,
      UserAttributes: [{ Name: 'custom:legacy_uid', Value: randomUUID() }],
    })
  );

  return event;
};
