# ADR-113: Training Log on Profiles
Date: 2026-10-12
Status: Accepted

## Context
Coaches need, on an athlete's or member's profile, the whole history of the
workouts they did together with how they performed. For members, they need
the classes they booked, the class's workout, and the member's result. Users
should see the same history on their own profile. The admin profile only
listed the latest 8 executions, plus separate score and class panels.

## Decision
- **Service.** `Application.GetTrainingLog` returns paged history (`offset`,
  `limit` ≤ 50, `next_offset`) of one of two kinds:
  - `workouts`: every execution, newest first, each with:
    - the workout summary (sections, format, timer, score type, exercises);
    - the performance (status, time, scale, section scores with section names
      and score types).
  - `classes`: past approved bookings, newest first, each with:
    - the class (name, type, duration, attendance);
    - the class's workout summary;
    - the member's latest execution of that booking, or nothing when no
      result was logged.

  It reads through the existing ports (`Execution`, `Scheduling` with a new
  `list_class_history/3`, `Workouts`).
- **Endpoints:**
  - `GET /api/org/:slug/admin/users/:id/history` (admins and coaches);
  - `GET /api/org/:slug/me/history` (own profile).
- **UI.** A shared `TrainingLog` component, used on the admin user profile and
  the user's own profile:
  - collapsed by default;
  - opens on Classes for members and Workouts for athletes;
  - one card per entry, putting the workout and the performance on the same
    surface;
  - pages load progressively as the user scrolls inside a bounded,
    independently scrollable area, with a "Show more" fallback.
- **Admin profile cleanup.** The truncated "Training history", "Scores" and
  "Class participation" panels on the admin profile are replaced by the log.

## Consequences
- **N+1 workout loads.** The workouts of a page are loaded per page (at most
  `limit` lookups).
- **Executions read in memory.** Executions are listed per user and sliced in
  memory. That is fine for gym-sized histories; move to SQL paging if a user
  accumulates thousands.

## Integration note (2026-10-13)

Main already had a different "training log" (ADR-118: standalone entries for
workouts done outside executions, `TrainingLogController`, `training-log.ts`).
When this line merged into main, its profile history was renamed so the two
features coexist: `GetTrainingHistory`, `TrainingHistoryController` (still
`/me/history` and `/admin/users/:id/history`), the `TrainingHistoryPage`
OpenAPI schema, and the web `training-history.ts` modules with the
`TrainingHistory` component. The history does not yet include ADR-118 entries
or the per-execution clock adjustments the dossier used to show (TD-095).
