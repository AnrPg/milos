# ADR-024: is_team_workout Field and Realtime Sync Infrastructure Fix
Date: 2026-06-13
Status: Accepted

## Context

Two orthogonal issues were addressed together because the realtime sync fix was a prerequisite for correctly observing the `is_team_workout` feature in production:

1. **Realtime sync not reaching the browser**: Athletes and gym members with the schedule or assigned workouts page already open did not see new classes or workout assignments appear live. The root cause was that the Caddyfile reverse-proxy only forwarded `/api/*` paths to Phoenix; all other paths, including the WebSocket handshake at `/socket/websocket`, were silently forwarded to Next.js (web:3000), which has no WebSocket handler. The WS connection failed silently and all `BroadcastUserSync` work already in the codebase had no effect in the browser.

2. **`is_team_workout` dimension missing from the data model**: Master workouts did not carry a `is_team_workout` boolean. Analytics, athlete UX, and admin UI could not distinguish team workouts (executed in pairs or groups) from individual workouts. The admin analytics summary also lacked any breakdown of completions by team vs individual dimension.

Both decisions had architectural implications requiring an ADR under the project's CLAUDE.md contract.

## Decision

### A — Caddyfile WebSocket Proxy Rule

Added an explicit routing rule before the Next.js catch-all:

```
reverse_proxy /api/*    api:4000
reverse_proxy /socket/* api:4000   ← new
reverse_proxy           web:3000
```

This ensures Phoenix Channels WebSocket handshakes and long-poll fallbacks at `/socket/*` reach the Phoenix application server.

### B — `is_team_workout` Full-Stack Feature

**Database**: New migration adds `:is_team_workout` boolean column (default `false`, `NOT NULL`) to `master_workouts`.

**Domain (Elixir)**:
- `MasterWorkout` schema: field added, all four changesets (`draft_changeset`, `update_draft_changeset`, `publish_changeset`, `create_changeset`) cast `:is_team_workout`.
- `EctoWorkoutStore`: `normalize_workout/1`, `normalize_assigned_workout/1`, and the inline draft map in `get_admin_workout` all expose `is_team_workout` in the normalised map.

**Analytics**:
- `EctoAnalyticsStore.analytics_summary/1` now includes `team_workouts: team_workout_summary(since)`.
- `team_workout_summary/1` joins `workout_executions` with `master_workouts` on `master_workout_id`, groups by `(user_id, is_team_workout)`, and returns:
  - `aggregate`: `%{team_count, individual_count, total_count}`
  - `by_user`: map of `user_id → %{team_count, individual_count, total_count}`

**Frontend (TypeScript / React)**:
- `WorkoutRecord` and `AssignedWorkoutPreview` API types gain `is_team_workout?: boolean`.
- `DraftWorkoutState` gains `isTeamWorkout: boolean`; Zustand store wires `setIsTeamWorkout`, `loadFromDraftData`, `resetDraft`, and `toApiPayload`.
- `CanvasHeader`: Team toggle button inserted between the type dropdown and the right-hand spacer, styled with amber highlight when active.
- `WorkoutAdminConsole`: amber "Team" badge in each workout card.
- `AssignedWorkoutsConsole`: Team indicator in month, week, and 3-day views.
- `AssignedWorkoutPanel`: Team badge in the workout header.
- `AdminAnalytics`: New "Team workout breakdown" section with three aggregate metric cards and a per-user JSON display.

### C — Missing BroadcastUserSync Calls

Seven application service files lacked `BroadcastUserSync` calls, meaning their domain events were never pushed to connected browsers:

| Service | Added scope(s) |
|---------|---------------|
| `SubmitReview` | `my_reviews` (athlete), `admin_reviews` (all admins) |
| `UpdateReviewStatus` | `admin_reviews`, `my_reviews` |
| `ReportInjury` | `my_wellbeing`, `admin_wellbeing` |
| `AdminReportInjury` | `my_wellbeing`, `admin_wellbeing` |
| `MarkInjuryHealed` | `my_wellbeing`, `admin_wellbeing` |
| `MarkMyInjuryHealed` | `my_wellbeing`, `admin_wellbeing` |
| `WriteAdminAthleteNote` | `admin_coaching` |

## Rationale

### Caddyfile proxy rule
The alternative — routing at the application level inside Next.js — would require a custom server and breaks Next.js's edge-runtime model. A single Caddy routing rule is the correct, minimal fix for a reverse-proxy topology. The `/socket/*` prefix is stable: it is the Phoenix default and is not expected to change.

### Storing `is_team_workout` on `master_workouts`
The field belongs to the master workout definition, not to individual assigned workouts or executions. Denormalising it to `workout_executions` at write time would create drift risk when a workout is re-published. Joining at read time in the analytics query is acceptable given analytics are not latency-critical. This matches the existing JOIN pattern used elsewhere in `EctoAnalyticsStore`.

### Toggle in CanvasHeader (not in a section-level field)
Team vs individual is a property of the whole workout, not of individual sections or exercises. Placing the toggle in the global header next to `type` makes the relationship clear. An alternative of embedding it in a sidebar settings panel was considered but rejected as it adds UI surface for a simple boolean.

### Separate analytics section (not merged into existing event totals)
Team workout breakdown is a distinct operational metric — gym operators need to track team class adoption separately from overall completion volume. Merging it into the `events` card would obscure the signal.

## Alternatives Considered

1. **Polling the Phoenix API from Next.js for live updates**: Rejected. The project already has a full Phoenix Channels infrastructure (`BroadcastUserSync`, `SyncChannel`, `RealtimeSyncBridge`). Adding polling would create a parallel real-time mechanism and violate the "Phoenix Channels for all real-time" architecture constraint in CLAUDE.md.

2. **`is_team_workout` as a tag/label on `WorkoutSection`**: Rejected. Team execution mode is a property of the entire workout session, not of one section. Section-level granularity would complicate the analytics JOIN and the UI without adding value.

3. **Aggregate-only team analytics (no per-user breakdown)**: Rejected. Per-user breakdown is operationally valuable for identifying which athletes participate in team vs individual modalities, and the data is already available in the grouped query rows at no extra DB cost.

4. **Separate `team_workout_executions` table**: Rejected. Would duplicate execution data, create consistency risk on re-publish, and violate the single-table execution model established in ADR-009.

## Consequences

- Phoenix WebSocket connections now correctly reach the backend. All existing `BroadcastUserSync` broadcasts (assigned workouts, schedule slots, landing page) are now live end-to-end in the browser.
- `is_team_workout` is exposed uniformly across admin list, athlete delivery, execution context, and analytics.
- **Migration required**: `mix ecto.migrate` must be run to apply `20260613100000_add_is_team_workout_to_master_workouts.exs` before the backend restarts.
- `WorkoutExecution` records created before the migration correctly resolve `is_team_workout: false` (the column default), so historical analytics figures will appear as all-individual until team workouts are published and executed.
- `AdminAnalytics` team breakdown section shows `n/a` / `0` values until real team workout completions exist in the database — this is correct behaviour (no synthetic data).
- The `admin_workouts` React Query key is not yet invalidated via `RealtimeSyncBridge` scope mapping; `WorkoutAdminConsole` handles this via the DOM `USER_SYNC_EVENT` directly, which works but is inconsistent with the scope-based invalidation pattern used elsewhere. This is deferred follow-up.

## Implementation Notes

- `Enum.sum_by/2` does not exist in the Elixir standard library. The initial implementation used it; corrected to `Enum.reduce(0, fn {_, _, count}, acc -> acc + count end)`.
- The `MIX_ENV=dev` build directory was owned by `root` (Docker artifact), preventing local `mix compile`. Compilation was verified clean using `MIX_ENV=test mix compile`. The dev build directory permission issue is pre-existing and unrelated to this change.
- TypeScript compilation (`npx tsc --noEmit`) passed with zero errors after all frontend changes.
