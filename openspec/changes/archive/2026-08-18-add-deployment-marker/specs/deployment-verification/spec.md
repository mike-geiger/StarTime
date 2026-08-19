## Purpose

What a running backend reports about its own provenance, and how a deploy confirms it actually took effect. Answers "is my code live?" without the toolchain that deployed it.

## ADDED Requirements

### Requirement: A running backend reports the revision it was built from

The system SHALL expose, without authentication, the stage it belongs to, an identifier of the source revision its code was built from, and whether that build came from a working tree with uncommitted changes.

#### Scenario: Asking a deployed backend what it is running

- **WHEN** the health endpoint is queried
- **THEN** it reports that it is healthy, which stage it is, the revision it was built from, and whether that revision was clean

#### Scenario: Built from a clean checkout

- **WHEN** the deployed code was built from a working tree with no uncommitted changes
- **THEN** it reports the build as clean, and the reported revision fully describes the running code

#### Scenario: Built from a modified working tree

- **WHEN** the deployed code was built from a working tree with uncommitted changes
- **THEN** it reports the build as dirty, since the revision alone no longer describes what is running

### Requirement: The reported revision is fixed when the deployment is built

The system SHALL determine the reported revision from the repository at the time the deployment is prepared, and SHALL report that same value for the life of the deployment. It SHALL NOT be derived at request time from the running environment.

A running Lambda has no access to the repository it came from, and anything it could infer about itself at request time would describe the runtime rather than the source. Capturing it at build time is what makes the value trustworthy.

#### Scenario: Two requests to the same deployment

- **WHEN** the health endpoint is queried twice against one deployment
- **THEN** both report the same revision

#### Scenario: A new revision is deployed

- **WHEN** a deployment is made from a different revision
- **THEN** the endpoint reports the new revision

#### Scenario: The same revision is deployed again

- **WHEN** the same revision is deployed a second time
- **THEN** the reported revision is unchanged

### Requirement: The health endpoint stays public and reports only what is safe to publish

The system SHALL keep the health endpoint reachable without credentials, and SHALL limit what it reports to the stage, the revision identifier, the dirty flag, and its health status. It SHALL NOT disclose infrastructure detail such as file paths, environment variables, account or resource identifiers, or configuration.

The endpoint's value is that it can be checked from anywhere by anyone holding the URL, which is the same reason it must not become a description of the deployment's internals.

#### Scenario: Checking without credentials

- **WHEN** the health endpoint is queried with no authentication
- **THEN** it answers

#### Scenario: Nothing else is revealed

- **WHEN** the health endpoint's response is inspected
- **THEN** it carries only health status, stage, revision, and the dirty flag

### Requirement: A production deploy verifies that it took effect

The system SHALL, after a production deploy reports success, check the deployed backend's reported revision against the revision that was intended, and SHALL fail the deploy operation when they do not match. An endpoint that cannot be reached SHALL be treated as a failed verification, never as a pass.

#### Scenario: The deploy landed

- **WHEN** verification runs and the deployed revision matches the intended one
- **THEN** the deploy is reported as verified

#### Scenario: The deploy did not land

- **WHEN** the deployed revision differs from the intended one
- **THEN** the operator is told the deploy did not take effect, and the operation reports failure

#### Scenario: The endpoint cannot be reached

- **WHEN** the health endpoint cannot be reached during verification
- **THEN** the operation reports failure rather than assuming success

#### Scenario: Deploying from a modified working tree

- **WHEN** a deploy is made from a working tree with uncommitted changes
- **THEN** it is not blocked, but the operator is told the running code exists in no commit

### Requirement: Verification confirms a deploy rather than standing in for it

The system SHALL treat a failed deploy as a failure regardless of what the health endpoint reports, and SHALL NOT run verification as a way of salvaging a deploy that already failed.

Verification covers one part of the deployment; the deploy's own result is what covers the rest. A reachable, correct-looking health endpoint says nothing about whether some other part of the deployment failed.

#### Scenario: The deploy itself fails

- **WHEN** the deploy reports failure
- **THEN** the operation stops and reports failure, without consulting the health endpoint

#### Scenario: One part of a deploy fails

- **WHEN** part of a multi-stack deploy fails while the health endpoint updates successfully
- **THEN** the operation still reports failure, because the deploy's own result governs
