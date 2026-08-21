## Context

`ChoresView` currently renders three sections per household member — Active (`choreStore.choresDueToday`), Recurring (`choreStore.recurringChores`), and Past (`choreStore.pastCompletions`) — all in one `List`. Only the Active section's rows have a tap gesture (`editingChore = chore`, opening `AddEditChoreView`) and swipe-to-delete; the Recurring and Past rows are plain `HStack`s with no interaction. `ProgressTabView` is a separate tab that already renders per-child sections (a points chart, a streak list) fed by the same shared `ChoreStore`. See proposal.md - Why for the motivation.

## Goals / Non-Goals

**Goals:**
- Shrink the main Chores screen to just the due-today list.
- Give parents a way to edit and delete recurring chores that mirrors how Active chores already work, so there's exactly one edit interaction to learn.
- Relocate completion history into the screen that already shows other historical/progress information, rather than inventing a third destination.

**Non-Goals:**
- Changing how recurrence, due-today computation, streaks, or completions work. This is a presentation/navigation change only; `ChoreStore`'s public surface is unchanged.
- Any backend or API change — editing a recurring chore reuses `PUT /chores/{choreId}`, the same route Active-chore edits already call.
- Redesigning `ProgressTabView`'s existing chart/streak sections beyond adding one more section.

## Decisions

**New `ManageChoresView`, reached via a toolbar button on `ChoresView`, visible to both roles.** Rather than a `NavigationLink` row or a new tab bar entry, a toolbar button (`ellipsis.circle` or similar, next to the existing `+`) keeps `ChoresView`'s tab-bar slot and navigation title unchanged and matches how `AddEditChoreView` is already presented — as a sheet or pushed view reachable from the main list without adding a fifth tab. The button and screen are shown for both parents and children: today, a child's own Chores screen already includes their Recurring section (the `else if let myUID` branch calls the same `assigneeSections` a parent sees), so gating the whole new screen to parents would remove schedule visibility a child already has. Instead, edit and delete are gated to `isParent` on the row itself — exactly the pattern `choreRow` already uses for Active chores (`if isParent { editingChore = chore }`, `if isParent { Button("Delete"...) }`), so a child can still see a recurring chore's schedule but gets no tap or swipe affordance.

**`ManageChoresView` reuses `AddEditChoreView` unmodified, and `ChoreStore.recurringChores(for:)`/`.deleteChore(_:)` unmodified.** The edit sheet already handles create vs. edit via its `editingChore` parameter; nothing about a recurring chore's fields differs from an Active one being edited today, so no new form logic is needed. `ManageChoresView` composes the same per-child section structure `ChoresView` and `ProgressTabView` already use (`ForEach(childMembers)` for a parent, self-view for a child), reusing `recurringChoreRow` (renamed to live on the new view) but adding the same `isParent`-gated tap-to-edit and swipe-to-delete modifiers `choreRow` already has.

**History moves into `ProgressTabView` as a new per-child section, not a new screen.** `ProgressTabView` already exists specifically to show a member's history (points over time, streaks); completions are one more facet of the same thing, and it already iterates the same `childMembers`/self-view split `ChoresView` uses. Reusing it avoids a fourth history-shaped destination in the app (Chores, Manage Chores, Progress, and a hypothetical fourth).

**Accessibility identifiers move with their rows.** `recurringChoreRow-<id>` now lives in `ManageChoresView`, `pastCompletionRow-<id>` in `ProgressTabView`. Both keep their existing id format; only their container view changes, so `StarTimeUITests.swift` needs its queries retargeted to open the new screen/tab first, not new selectors.

**Alternatives considered:** A fifth tab was rejected (per your answer) to avoid crowding the tab bar for a feature used occasionally, not daily. Folding history into `ManageChoresView` alongside recurring chores (single "Manage" screen with two sections) was rejected in favor of splitting, per your answer — history is progress-shaped information both roles already see in Progress, while recurring-chore editing is a parent-only action layered onto a screen both roles can open.

## Risks / Trade-offs

- **A parent editing a recurring chore's recurrence (e.g., daily → weekly-Tuesdays) changes what shows up in today's Active list**, same as it already does when editing an Active chore. No new risk — `choresDueToday` already recomputes from `chore.recurrence` on every read.
- **Moving `pastCompletionRow` into `ProgressTabView` couples two previously-separate views' accessibility identifiers to one file.** Mitigated by keeping the identifier itself unchanged, so any test asserting on the identifier string (not the screen) still passes.
- **`ManageChoresView` being visible to children too means the accessibility tree gains a reachable screen with no parent-only guard at the navigation level**, only at the row-action level. This mirrors the existing Active-chore precedent exactly (`choreRow` is visible to children with edit/delete gated inline), so it introduces no new class of risk, just the same pattern in a second view.
