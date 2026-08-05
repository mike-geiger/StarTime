import type { PreSignUpTriggerHandler } from 'aws-lambda';

// Matches today's Firebase behavior, where createUser signs the user in
// immediately with no separate email-verification step.
export const handler: PreSignUpTriggerHandler = async (event) => {
  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = true;
  return event;
};
