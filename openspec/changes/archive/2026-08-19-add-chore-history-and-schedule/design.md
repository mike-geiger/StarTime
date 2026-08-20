## Context

`ChoresView` currently renders one section per assignee (per child for a parent, or just "mine" for a child), each populated by `ChoreStore.choresDueToday(for:)`. `ChoreStore.refreshNow()` already fetches the full `chores` array and up to 60 days of `completions` on every refresh — the data this change needs to display is already client-side; nothing here requires a new network call. See proposal.md for motivation and `specs/chore-tracking/spec.md` for the behavior contract.

Existing derived-view helpers on `ChoreStore` (`choresDueToday(for:)`, `isCompletedToday(_:)`, `streak(for:)`) compute over `@Published` state rather than the View reaching into raw arrays — this is the established convention (also used by `RewardStore.balance(for:)`) and this change follows it.

## Goals / Non-Goals

**Goals:**
- Add "Recurring" and "Past" derived views alongside the existing due-today ("Active") view, computed from data `ChoreStore` already holds.
- Preserve today's due-today behavior and its accessibility identifiers unchanged, so existing UI tests keep passing without modification.
- Apply the same three-section structure to both the parent's per-child view and the child's own view (see proposal.md's assumption on scope).

**Non-Goals:**
- No date picker, calendar, or arbitrary-day navigation (explicitly ruled out by the user).
- No "missed" detection — Past shows actual completions only, not due-but-never-completed occurrences. Computing due-status retroactively for arbitrary past days per chore is materially more logic than "show what was completed," and wasn't asked for.
- No pagination or new fetch window — Past is bounded by whatever `ChoreStore` already holds (currently 60 days); tuning that window is an existing, isolated knob and not part of this change.
- No backend, API, or DynamoDB changes.

## Decisions

1. **New derived-view helpers live on `ChoreStore`, not computed inline in the View.**
   Add `recurringChores(for uid: String?) -> [Chore]` and `pastCompletions(for uid: String?) -> [ChoreCompletion]`, mirroring `choresDueToday(for:)`.
   *Alternative considered*: compute inline in `ChoresView`. Rejected — it would duplicate filtering logic between the parent's per-child loop and the child's own-chores branch, and breaks the established Store-owns-derived-state convention.

2. **Recurring schedule text is a model-level computed property**, e.g. `Chore.scheduleDescription: String` ("Daily", "Mon, Wed, Fri"), since it's a pure function of `recurrence`/`weeklyDays` with no dependency on store state.
   *Alternative considered*: compute the string in the View or on the Store. Rejected — it doesn't depend on anything the Store or View owns, so it belongs with the rest of the model's own logic.

3. **`recurringChores(for:)`** returns chores where `recurrence != .once`, filtered by assignee, sorted by title for stable ordering. It is independent of whether each chore is due today — that's the point of the requirement.

4. **`pastCompletions(for:)`** returns `completions` filtered by assignee (via `completedByUID`), sorted most-recent-first. Rendered as a flat reverse-chronological list (chore title, points, relative date), not grouped into per-day sub-sections — the parent view already nests one level (per-child); a second nesting level (per-day) inside that was judged more complexity than the ask warranted. `ForEach`/`List` in SwiftUI renders lazily, so a few hundred rows across a 60-day window is not expected to be a scroll-performance concern.

5. **Section layout**: keep the existing per-assignee grouping as the outer structure (a parent still sees one block per child, as today), and within each assignee's block render three consecutive `Section`s in a fixed order — Active, Recurring, Past — each titled to include the assignee's name (e.g. "Emma — Active"). List sections in SwiftUI can't visually nest, so "sub-group" means a second-level `Section`, not an indented sub-list.
   *Alternative considered*: a segmented control (Active/Recurring/Past tabs) swapping the whole list's content. Rejected — it hides two of the three groups at a time, whereas the user's framing (wanting past, active, and recurring "sections") reads as concurrently visible, not a picker.

6. **Existing accessibility identifiers are untouched.** `completeChoreButton-<choreId>` stays scoped to Active-section rows only — Recurring rows show schedule only (not completable from there) and Past rows are historical/immutable. Existing UI tests query by identifier, not list position, so they keep passing regardless of the new surrounding sections.

7. **New rows get their own identifiers** (e.g. `recurringChoreRow-<choreId>`, `pastCompletionRow-<completionId>`) so future UI tests can target them; adding those tests is left to `tasks.md` to decide, not required for this change to be correct.

## Risks / Trade-offs

- [Risk] Past is unbounded within the store's 60-day fetch window; a very active household could produce a long flat list. → Mitigation: SwiftUI's lazy rendering should absorb this; if it doesn't, the fetch window is already an isolated constant in `ChoreStore.refreshNow()`, adjustable independently of this change.
- [Risk] Three sections per child (versus one today) makes the parent's Chores tab longer, especially with several children. → Mitigation: none built into this change (no collapse/expand was requested); worth revisiting only if it proves to be a real usability problem after shipping.
- [Risk] Extending the three-section layout to the child's own view is an assumption recorded in proposal.md, not an explicit ask. → Mitigation: low incremental cost, since it reuses the same store helpers and section-rendering code already being written for the parent path; trivial to gate behind `isParent` later if wrong.

## Migration Plan

Purely client-side; no data migration. Ship as a normal client release — no backend deploy required for this change itself, though the full UI test suite should still run against an ephemeral stack before merging, per existing convention, since `ChoresView` is touched. Rollback is a plain revert; no server-side state to unwind.

## Open Questions

- Should a Recurring row also carry a lightweight "due today" indicator, or is the schedule text (e.g. "Mon, Wed, Fri") sufficient on its own? Deferrable to implementation — doesn't change the spec or task breakdown either way.
- Exact relative-date formatting in Past ("Today" / "Yesterday" vs. a raw date) is a presentation detail that can be decided while implementing `tasks.md`.
