import type { PreSignUpTriggerHandler } from 'aws-lambda';

// Sign-up puts the user straight into the app: no emailed confirmation code,
// no verification step. Deliberate for a family app where a parent sets up
// accounts for kids who may not have reachable email.
export const handler: PreSignUpTriggerHandler = async (event) => {
  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = true;
  return event;
};
