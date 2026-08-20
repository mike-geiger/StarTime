## Why

`ChoresView` only ever shows chores due *today* (`ChoreStore.choresDueToday`). A weekly chore due Mon/Wed/Fri simply disappears from the list on every other day, and there is no way to look back at what was already completed. A parent has no way to confirm a recurring chore is actually configured correctly on an off-day, or to review a child's completion history, without going around the app entirely.

## What Changes

- `ChoresView` gains three sections per assignee, replacing the current single "due today" list:
  - **Active** — today's to-do list: chores currently due and not yet completed, plus completed-today chores shown checked off. This is the existing due-today behavior, kept as-is but now one section among three.
  - **Recurring** — every daily/weekly chore assigned to that member, shown regardless of whether it is due today, with a human-readable schedule (e.g. "Daily", "Mon, Wed, Fri") so a parent can see the full recurring schedule on any day.
  - **Past** — completion history (chore title, points, who, when), most recent first, drawn from the completions the store already fetches (60-day lookback). One-time chores that have been completed appear here rather than in Active.
- `ChoreStore` gains derived-view helpers for the Recurring and Past groupings (`recurringChores(for:)`, `pastCompletions(for:)` or equivalent), following the existing pattern of `choresDueToday`/`streak`.
- Applies to both roles: a parent sees the three sections per child (as today, grouped in child sections), and a child sees the same three sections for their own chores. Today only the parent's per-child grouping showed anything beyond "due today"; the child's own view gets the same expansion for consistency, since it is the same underlying data through the same store.
- No calendar/date-picker UI — sections are always relative to "now," not an arbitrary selected day.
- No backend changes: `ChoreStore` already fetches chores and up to 60 days of completions; this change only reorganizes how the client already-fetched data is displayed.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `chore-tracking`: adds requirements that recurring chores remain visible (with their schedule) on days they are not due, and that completed chores are visible as history, independent of the existing "due today" requirement.

## Impact

- `StarTime/Views/ChoresView.swift` — restructured into three sections per assignee (Active / Recurring / Past) instead of one due-today list.
- `StarTime/Services/ChoreStore.swift` — new read-only derived-view helpers alongside `choresDueToday`/`isCompletedToday`/`streak`; no change to `refresh`/`start`/`stop`/mutation methods.
- Possibly `StarTime/Models/Chore.swift` — a small helper to render `recurrence`/`weeklyDays` as a display string (e.g. "Mon, Wed, Fri"), if one doesn't already exist.
- No API, Lambda, or DynamoDB changes.
- No new accessibility identifiers are strictly required by existing UI tests, but new ones will be needed for the added sections/rows if UI tests are extended to cover them (left to `tasks.md`/`design.md` to specify).
