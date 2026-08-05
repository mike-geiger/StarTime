import type { UserMigrationTriggerHandler } from 'aws-lambda';

interface FirebaseSignInResponse {
  localId: string;
  email: string;
}

// Lets a family member who already has a Firebase account keep signing in
// with their existing email/password after cutover, with no password reset.
// Cognito calls this the first time it sees a sign-in attempt for an email
// it doesn't recognize; a successful verification here tells Cognito to
// create the account transparently and complete the sign-in in one step.
//
// Requires the App Client to use USER_PASSWORD_AUTH (see auth-stack.ts) --
// Cognito's SRP flow never sends the plaintext password, so it can't support
// migration. Only reachable for real during the Phase 6 cutover; ephemeral
// test stacks have no matching Firebase accounts to migrate, so every sign-up
// there goes through the normal SignUp path instead.
export const handler: UserMigrationTriggerHandler = async (event) => {
  if (event.triggerSource !== 'UserMigration_Authentication') {
    throw new Error('Unsupported trigger source for user migration');
  }

  const firebaseWebApiKey = process.env.FIREBASE_WEB_API_KEY;
  if (!firebaseWebApiKey) {
    throw new Error('FIREBASE_WEB_API_KEY is not configured');
  }

  const email = event.userName;
  const password = event.request.password;

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${firebaseWebApiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: false }),
    }
  );

  if (!response.ok) {
    // Wrong password or no such Firebase account -- surface as a normal
    // Cognito sign-in failure, not a server error.
    throw new Error('Incorrect username or password.');
  }

  const firebaseUser = (await response.json()) as FirebaseSignInResponse;

  event.response.userAttributes = {
    email: firebaseUser.email,
    email_verified: 'true',
    'custom:legacy_uid': firebaseUser.localId,
  };
  event.response.finalUserStatus = 'CONFIRMED';
  event.response.messageAction = 'SUPPRESS';

  return event;
};
