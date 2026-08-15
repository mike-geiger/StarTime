# Authentication Specification

## Purpose

Identity for the app: account creation, sign-in, session persistence across launches, account deletion, and the migration path that let accounts originally created in Firebase keep working after the move to AWS Cognito.

## Requirements

### Requirement: Account creation signs the user in immediately

The system SHALL sign a new user in as part of sign-up, with no separate email-verification step.

#### Scenario: New user signs up

- **WHEN** a user submits an unused email address and a password meeting the password policy
- **THEN** the account is created, confirmed automatically, and the user is signed in without any further interaction

#### Scenario: Email already registered

- **WHEN** a user submits an email address that already has an account
- **THEN** sign-up fails with a message telling them the address is taken, and no account is created

### Requirement: Every account carries a stable application user id

The system SHALL assign each account an immutable application-level user id, distinct from any identifier the authentication provider generates for its own use, and SHALL use that id as the key for all household, chore, reward, and balance data.

This exists because the identity provider's own subject id is regenerated per provider and can never match an id issued by a previous provider. Keying application data on a separate, stable id is what allows the provider to be replaced without the data becoming unreachable.

#### Scenario: Fresh sign-up receives an application user id

- **WHEN** a brand-new account is confirmed
- **THEN** the system generates a unique application user id and attaches it to the account, and it appears in the account's identity token

#### Scenario: Application user id never changes

- **WHEN** a user signs in repeatedly, across sessions and devices
- **THEN** the application user id in their token is identical every time

### Requirement: Accounts from the previous provider migrate on first sign-in

The system SHALL allow a user whose account was created under the previous authentication provider to sign in with their existing email and password, without a password reset, and SHALL preserve their original user id so their existing data remains theirs.

#### Scenario: Legacy user signs in for the first time

- **WHEN** a user with no account in the current provider signs in with credentials valid in the previous provider
- **THEN** an account is created transparently, their original user id is preserved as the application user id, their email is marked verified, and the sign-in succeeds in that single attempt

#### Scenario: Legacy user supplies the wrong password

- **WHEN** a user with no account in the current provider signs in with credentials the previous provider rejects
- **THEN** the sign-in fails as an ordinary bad-credentials error and no account is created

### Requirement: Sessions survive app relaunch

The system SHALL persist a signed-in session in the device keychain and restore it on launch, and SHALL show a loading state while restoring rather than briefly displaying the sign-in screen.

#### Scenario: Returning user launches the app

- **WHEN** a user who signed in previously and did not sign out launches the app
- **THEN** the app restores their session and takes them to their household without prompting for credentials

#### Scenario: Stored session is no longer valid

- **WHEN** the stored session cannot be renewed
- **THEN** the stored credentials are discarded and the user is shown the sign-in screen

### Requirement: Expired access is renewed without interrupting the user

The system SHALL detect a rejected request caused by an expired token, renew the session, and retry the request once. A second rejection SHALL surface to the caller rather than retrying indefinitely.

#### Scenario: Token expires mid-session

- **WHEN** a request is rejected because the identity token has expired
- **THEN** the session is renewed and the request is retried once, succeeding without the user noticing

#### Scenario: Session cannot be renewed

- **WHEN** a request is rejected and renewal also fails
- **THEN** the failure is reported to the caller and the user is treated as signed out

### Requirement: Account deletion removes data before removing the account

The system SHALL delete a user's application data before deleting their authentication account, and SHALL abort without deleting the account if the data cleanup fails.

Deleting the account first would leave data belonging to a user who can no longer sign in to remove it.

#### Scenario: User deletes their account

- **WHEN** a user confirms account deletion and the data cleanup succeeds
- **THEN** their authentication account is deleted and they are returned to the sign-in screen

#### Scenario: Data cleanup fails during deletion

- **WHEN** a user confirms account deletion and the data cleanup fails
- **THEN** the authentication account is left intact, an error is shown, and the user can retry
