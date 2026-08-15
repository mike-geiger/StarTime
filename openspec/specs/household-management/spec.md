# Household Management Specification

## Purpose

The household is the unit every other capability is scoped to: chores, rewards, completions, and balances all belong to one. This covers creating a household, joining one by invite code, member roles, and what happens to a household's data when its members leave.

## Requirements

### Requirement: A signed-in user belongs to at most one household

The system SHALL route a signed-in user with no household to a setup screen offering household creation or joining, and SHALL route a user who has one into the app.

#### Scenario: New user has no household

- **WHEN** a user signs in and has no household
- **THEN** they are shown the choice to create a household or join one with an invite code

#### Scenario: Existing member opens the app

- **WHEN** a user who belongs to a household signs in
- **THEN** they are taken straight to their household's chores

### Requirement: Creating a household makes the creator a parent

The system SHALL create the household and the creator's membership as a single atomic operation, with the creator holding the parent role.

Partial creation would leave either a household nobody belongs to or a user pointing at a household that does not exist.

#### Scenario: User creates a household

- **WHEN** a user submits a household name and their display name
- **THEN** the household is created with them as its only member, holding the parent role, and they are taken into the app

#### Scenario: Creation cannot half-succeed

- **WHEN** any part of household creation fails
- **THEN** neither the household nor the membership record is left behind

### Requirement: Parents invite others with single-use-per-role codes

The system SHALL allow a parent to generate a short invite code carrying a role, and SHALL reject code generation from a member who is not a parent. Codes SHALL be verified unique at generation time.

Role enforcement lives on the server, not only in the interface, so it cannot be bypassed by a modified client.

#### Scenario: Parent generates an invite code

- **WHEN** a parent requests an invite code for a given role
- **THEN** a unique code is generated, displayed to them, and remains valid until used or its household is deleted

#### Scenario: Child attempts to generate an invite code

- **WHEN** a member holding the child role requests an invite code
- **THEN** the request is refused

#### Scenario: Generated code collides with an existing one

- **WHEN** a newly generated code matches one already in use
- **THEN** the system generates another rather than overwriting the existing code's household

### Requirement: Joining with a valid code adds the user with the code's role

The system SHALL add a user to the household named by a valid invite code, with the role the code carries.

#### Scenario: User joins with a valid code

- **WHEN** a user submits a valid invite code and their display name
- **THEN** they become a member of that household with the code's role and are taken into the app

#### Scenario: User submits an unrecognized code

- **WHEN** a user submits a code that does not exist
- **THEN** they are told the code is not valid and remain on the join screen

#### Scenario: Code points at a deleted household

- **WHEN** a user submits a code whose household has since been deleted
- **THEN** they are told the code is not valid, in the same terms as an unrecognized code

### Requirement: A departing member's data outlives them only if others remain

The system SHALL remove a departing member from the household when other members remain, and SHALL delete the household and all of its data when the departing member is the last one.

#### Scenario: One of several members leaves

- **WHEN** a member leaves a household that has other members
- **THEN** only their membership is removed; the household, its chores, rewards, and history are untouched, and remaining members are unaffected

#### Scenario: The last member leaves

- **WHEN** the last remaining member leaves
- **THEN** the household and all of its chores, completions, rewards, redemptions, balances, and invite codes are deleted

### Requirement: Household deletion leaves nothing orphaned

The system SHALL delete a household's dependent records before the household record itself, so that an interrupted deletion leaves a household that can be retried rather than unreachable records with nothing pointing at them.

#### Scenario: Deletion is interrupted partway

- **WHEN** household deletion fails after removing some dependent records
- **THEN** the household record still exists and retrying the deletion completes the cleanup

#### Scenario: Invite codes are swept with the household

- **WHEN** a household is deleted
- **THEN** every invite code issued for it is deleted too, including codes never redeemed
