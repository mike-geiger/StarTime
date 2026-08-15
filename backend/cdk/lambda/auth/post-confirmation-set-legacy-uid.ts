import type { PostConfirmationTriggerHandler } from 'aws-lambda';
import { randomUUID } from 'node:crypto';
import {
  AdminUpdateUserAttributesCommand,
  CognitoIdentityProviderClient,
} from '@aws-sdk/client-cognito-identity-provider';

const client = new CognitoIdentityProviderClient({});

// Stamps the canonical app-level user id (custom:legacy_uid) onto every
// account at sign-up. Every Lambda keys off that claim rather than Cognito's
// `sub`, because `sub` is regenerated per user pool -- the id has to be one
// this app controls, not one the identity provider owns.
//
// Guarded to PostConfirmation_ConfirmSignUp so the trigger's other sources
// (e.g. a forgot-password confirmation) can't overwrite an existing uid.
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
