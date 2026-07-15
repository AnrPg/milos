# ADR-013: Phase 8 UX Improvements and Production Fixes
Date: 2026-06-10
Status: Accepted

## Context
After completing the core feature phases (1-7), a production-readiness audit
identified correctness bugs in the Elixir backend and a set of UX gaps in the
web frontend. The changes span: GenServer initialization ordering, an unsafe
`List.last/1` call on empty lists, dead module cleanup, duplicate infrastructure
code, redundant pre-lock guards, shallow validation in a publish command, missing
`@impl true` annotations, and several frontend UX improvements requested by the
product owner.

The frontend requests covered: full workout previews in schedule slot sidepanels,
a sticky sidepanel header (the Close button was obscured by the top nav),
workout-type color coding, role-based nav label changes, login default tab fix,
notification inbox improvements, and URL-based draft ID persistence in the
workout authoring canvas.

## Decision

### Backend fixes

**GenServer PubSub subscribe ordering**: Move `Phoenix.PubSub.subscribe/2` from
`init/1` to `handle_continue(:subscribe, state)` in
`WorkoutCompletionHandler`. Subscribing inside `init/1` races with the
supervisor tree starting; the `handle_continue` callback fires only after the
GenServer is registered and the supervisor has returned, which guarantees the
process is ready to handle messages before any can arrive.

**`List.last/1` crash on empty list**: `build_stats/4` in
`RecordWorkoutCompletion` used `List.last(completed_executions)` which returns
`nil` and crashes the subsequent `.completed_at_utc` field access when the list
is empty (e.g., the very first execution for a user). The fix passes the current
execution as a fallback via the two-argument safe form
`List.last(completed_executions, current_execution)` and threads the current
execution through as `build_stats/5`.

**Dead `TokenStore` module removed**: The `infrastructure/security/token_store.ex`
file was an unreferenced copy of application-layer token logic. The correct
surface is `Application.TokenStore`. The dead file was deleted.

**`@impl true` missing on UserStore and EctoGamificationStore**: Elixir requires
`@impl true` annotations on every callback implementation when a module declares
`@behaviour`. The missing annotations were added to all 8 delegating functions
in `UserStore` and to the `false` clause of `set_leaderboard_opt_in/2` in
`EctoGamificationStore`. This makes behaviour mismatches a compile-time error
instead of a silent runtime dispatch failure.

**LandingCache `invalidate/1` duplication**: `invalidate/1` duplicated the body
of `batch_invalidate/1`. Consolidated to a single-element delegation:
`batch_invalidate([user_id])`.

**Redundant pre-lock `completed_at_utc` guard**: `CompleteExecution` checked
`execution.completed_at_utc != nil` before acquiring the database row lock.
The infrastructure adapter already handles the idempotency check under the FOR
UPDATE lock. The redundant guard was removed so the only authoritative check is
the one that runs under the lock.

**Shallow publish guard in `EctoWorkoutStore`**: `publish_workout/2` only
checked `sections == []` for the "no content" guard. A draft with sections that
each have an empty exercises list would pass and produce a published workout with
no exercises. The check was deepened to fail with `:no_sections` when all
sections have empty exercise lists, matching the intent of the original guard.

**Full workout preview in schedule calendar**: `GetScheduleCalendar.preview_workout/1`
previously mapped only top-level workout fields (id, title, type, sections with
name/order, exercise names only). The full exercise prescription fields (sets,
prescription_value/unit, load_value/mode, tempo, rest, HR zone, pacing,
interval_assignment, superset_group_id, cluster/rest-pause fields) and scale
variations (with their nested scale_level) are now included. This required no
schema changes — the preload depth was already correct in `EctoWorkoutStore`.

### Frontend changes

**`WorkoutPreviewDetail` shared component**: A new shared component renders the
full workout preview (sections → exercises with prescription badge, extras chips,
section timer, and active scale variations). Used in `SlotPopup` and will be
used in the `AssignedWorkoutPanel` (Phase 2).

**`SlotPopup` sticky header**: The Close button was obscured by the sticky top
nav (`z-50`, `3.25rem` height). The fix adds a sticky header row inside the
panel that sits at `z-10`, clearing the nav when the content scrolls. The close
action is also triggered by clicking the backdrop overlay.

**Participation approval and booking deadline display**: The schedule slot info
boxes now show "By coach" / "Auto-confirmed" (replacing the ambiguous
"Approval" label) and "Deadline to book" with both a relative string and an
exact datetime (replacing "Timeout: 60m").

**Workout type color coding**: A shared `TRAINING_TYPE_COLORS` record is exported
from `SlotPopup` and consumed by `CalendarView` and `TypeFilterChips`. All
workout types use a warm terracotta-to-clay palette (crossfit→darkest red,
recovery→warmest brown) so training types are visually distinguishable without
using arbitrary semantic colors.

**Role-based nav labels**: Admins now see "Class Schedule" (for `/schedule`) and
"Athletes' Workouts" (for `/my-workouts`) in the top nav, matching the admin
perspective of those pages.

**Login default tab**: `AuthConsole` now defaults to `"login"` mode instead of
`"register"`, matching the expected default entry point for returning users.

**Notification inbox collapsible sections**: `NotificationBell` now separates
notifications into "New" (unread, always open) and "Read" (collapsed by default,
toggled with ▲/▼). Unread count badge and "Mark all read" appear in the "New"
section header.

**URL-based draft ID persistence**: `WorkoutCreationCanvas` now writes the draft
ID into the URL via `router.replace("/admin/workouts/new?draft=<id>")` after
creating a new draft. If `?draft=<id>` is already in the URL (e.g., on page
refresh or returning from the admin list via a "Continue editing" link), the
canvas resumes the existing draft instead of creating a new one. The admin
workout list shows a "Continue editing" link for draft-status workouts pointing
to `/admin/workouts/new?draft=<id>`.

## Rationale

All backend fixes address demonstrable correctness failures (crash on empty list,
race condition in GenServer init, silent behaviour dispatch failures) or
unnecessary complexity (dead code, duplicate logic, redundant guards). The fixes
are minimal and additive — no architectural boundaries were changed.

The frontend changes were driven by direct product owner feedback after testing
the Phase 7 build. The shared `WorkoutPreviewDetail` component avoids duplicating
the exercise-rendering logic between the schedule sidepanel and the upcoming
my-workouts sidepanel (Phase 2). The color system is centralized to avoid
per-component drift as more surfaces consume training type data.

## Alternatives Considered

**Keeping PubSub subscribe in `init/1`**: Acceptable in practice because Phoenix
application start order is deterministic, but `handle_continue` is the documented
OTP pattern for post-init side effects and eliminates the dependency on the
supervisor ordering being stable under future refactors.

**Using `Enum.at(-1, fallback)` instead of `List.last/2`**: Equivalent; `List.last/2`
is the idiomatic Elixir form and explicit about the fallback contract.

**Separate `WorkoutPreviewDetail` per panel**: Rejected — the prescription
display rules are identical for both the schedule sidepanel and the
athlete-assigned workout panel. A single component with typed props is
preferable to copy-paste.

## Consequences

The schedule API now returns substantially more data per workout preview (full
exercise trees + variations). Callers that previously used only `workout.title`
and `workout.sections[].name` are unaffected — the new fields are additive.
A future optimization could add a `?preview=minimal` query flag for clients
that don't need the full tree.

Draft ID URL persistence means that refreshing `/admin/workouts/new` without a
`?draft` param creates a new draft — there is no automatic recovery if the URL
is navigated away from and the `?draft` param is lost. This is an acceptable
trade-off given that all drafts are visible in the admin workout list.

## Implementation Notes

The `preview_workout/1` full-tree expansion needed no migration — the preload
depth in `EctoWorkoutStore.list_schedule_workouts/0` already included
`[sections: [exercises: [variations: [:scale_level]]]]`. Only the application
service mapping function was shallow.

The `TRAINING_TYPE_COLORS` export from `SlotPopup.tsx` creates an implicit
dependency between that file and `CalendarView` / `TypeFilterChips`. A future
refactor should move the constant to a shared `workoutTypes.ts` utility if the
number of consumers grows.

Notification read/unread state in the frontend is currently local (in-memory
state derived from the fetched notification list). "Mark all read" calls the API
but the local state is also updated optimistically to avoid a round-trip visible
flash. This pattern should be revisited if optimistic updates and background
refresh polling cause consistency issues.

Phase 2 deferred items still outstanding:
- Booking withdrawal endpoint (`DELETE /bookings/:id`)
- Athlete workout rejection (`athlete_status` on `assigned_workout_athletes`)
- `workout_deleted` vs `workout_changed` notification differentiation
- `AssignedWorkoutPanel` in my-workouts (with `WorkoutPreviewDetail` + message CTA)
- Draft deletion on publish
- Push notifications → inbox behavior and profile settings
