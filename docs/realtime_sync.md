# Realtime Sync Matrix

Date: 2026-06-11

## Purpose
This document defines which UI surfaces update live, which Phoenix channel or
user-scoped invalidation scope they depend on, and which backend write paths are
responsible for emitting refresh events.

The contract is intentionally lightweight:

- Phoenix Channels carry invalidation events, not authoritative read models.
- REST remains the source of truth for screen data.
- User-scoped sync uses `sync:{user_id}` and the `sync:refresh` event.
- Dedicated channel topics remain in place for schedule, notifications, and
  active execution sessions.

## Channel Topics

| Topic | Event | Purpose |
|---|---|---|
| `schedule:lobby` | `schedule:refresh` | Refresh class schedule and workout browse week views |
| `notifications:{user_id}` | `notifications:changed` | Refresh notification bell/inbox |
| `execution:{execution_id}` | `execution:progress_updated`, `execution:note_submitted`, `execution:completed` | Live execution screen updates |
| `sync:{user_id}` | `sync:refresh` | User-scoped invalidation for landing, assigned workouts, and admin read models |

## User-Scoped Sync Scopes

### `landing`
- Client reaction:
  - invalidates `["landing"]`
  - invalidates `["execution"]` so landing execution detail refetches after completion
- Surfaces:
  - `/`
  - athlete `coach_notes`
  - landing challenge progress
  - landing execution completion summary
  - leaderboard visibility/runtime setting changes on landing
- Backend emitters:
  - `InvalidateLandingPages.for_user/1`
  - `InvalidateLandingPages.for_users/1`
  - `InvalidateLandingPages.for_all_users/0`
- Triggered by:
  - workout completion
  - admin -> athlete coaching notes
  - leaderboard preference changes
  - challenge create/update/delete
  - admin settings updates

### `assigned_workouts`
- Client reaction:
  - `AssignedWorkoutsConsole` reruns `fetchAssignedWorkoutWeek`
- Surfaces:
  - `/my-workouts`
  - admin assignment calendar/list in the same console
- Backend emitters:
  - `AssignWorkout`
  - `UpdateAssignedWorkout`
  - `DeleteAssignedWorkout`
  - `RejectAssignedWorkout`
  - `PublishWorkout` when a republish or substitute affects assignments
- Triggered by:
  - assignment create/update/delete/reject
  - workout republish/substitution affecting existing assignments

### `admin_challenges`
- Client reaction:
  - invalidates `["admin", "challenges"]`
- Surfaces:
  - `/admin/challenges`
  - challenge list
  - challenge detail/participant progress
- Backend emitters:
  - `CreateSeasonalChallenge`
  - `UpdateSeasonalChallenge`
  - `DeleteSeasonalChallenge`
  - `CompleteWorkout` for participant progress movement

### `admin_settings`
- Client reaction:
  - invalidates `["admin", "settings"]`
- Surfaces:
  - `/admin/settings`
- Backend emitters:
  - `UpdateAdminSettings`

### `admin_workouts`
- Client reaction:
  - `WorkoutAdminConsole` reloads workout list and scale levels
  - `WorkoutCreationCanvas` reloads scale levels
  - `WorkoutCreationCanvas` refetches the currently open draft/workout when the
    payload id matches and the event originated from a different editor session
- Surfaces:
  - `/admin/workouts`
  - `/admin/workouts/new`
  - reopened/duplicated/published draft editor tabs
- Backend emitters:
  - `CreateDraftWorkout`
  - `UpdateDraftWorkout`
  - `CreateWorkoutWithSections`
  - `ReopenWorkout`
  - `DuplicateWorkout`
  - `PublishWorkout`
  - `DeleteWorkout`
  - `ReplaceScaleLevels`

## Dedicated Realtime Surfaces

### Schedule
- Surface:
  - `/schedule`
  - `/workouts` week browser
- Topic:
  - `schedule:lobby`
- Triggered by:
  - booking submit/resolve/timeout
  - slot create/update/delete
  - workout updates affecting scheduled slots

### Notifications
- Surface:
  - notification bell and inbox popover
- Topic:
  - `notifications:{user_id}`
- Triggered by:
  - notification persistence changes
- Notes:
  - athlete/admin freeform messages currently surface as notifications, not as a
    separate chat thread read model

### Active Execution
- Surface:
  - workout execution mode screen
- Topic:
  - `execution:{execution_id}`
- Triggered by:
  - progress updates
  - execution notes
  - completion

## Frontend Bridge

`apps/web/src/components/realtime-sync-bridge.tsx` owns the authenticated
subscription to `sync:{currentUser.id}`.

It translates socket payloads into:

- React Query invalidations for query-backed pages
- `window` `CustomEvent`s for non-query screens that already have imperative load
  functions

The browser event name is `milos:user-sync` and is normalized by
`apps/web/src/lib/user-sync.ts`.

## Notes On Message-Like Features

- Admin -> athlete coaching notes now update the athlete landing page live via
  the `landing` scope.
- Athlete -> admin messages from schedule or assigned workouts continue to be
  delivered live through notifications.
- There is no separate chat-thread read model in the app today, so there is no
  additional thread view to invalidate.
