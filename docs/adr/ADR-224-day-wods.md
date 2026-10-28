# ADR-224: Day WODs: one WOD for a whole day, inherited by its classes
Date: 2026-10-28
Status: Accepted

## Context
ANR (2026-10-28): a WOD must be assignable to a whole date, so that every class
of that day, or every class of chosen types, uses the same WOD. Until now a WOD
was linked class by class (ADR-176), so a box with eight classes a day linked
the same WOD eight times, and a class added later in the day started as a draft
that sent missing-WOD alerts.

Prior art: Kilo lets staff assign a workout to "this class only" or "all classes
of the same type on that day", and shows each class's assignment status.
Calendars show whole-day items in a strip above the time grid (DayPilot, MUI
Scheduler). Unity's inheritance pattern marks overridden values and offers
"revert to inherited". Bulk-action guidance asks for the exact count and the
exceptions before confirming (Basis, AppMaster).

## Decision
1. **Model.** `day_workouts` holds rules: `(organization, local_date,
   class_type_id?, location_id?) → master_workout_id`, unique per scope with
   `NULLS NOT DISTINCT`. A null type means every class; a null branch means
   every branch. `local_date` is the gym's own date (ADR-176). The WOD is the
   copy filed in that day's Classes folder (`ClassWorkoutFiling`), shared by
   every class of the day.
2. **Inheritance is written onto the class.** A class that follows a rule gets
   the rule's WOD in `scheduled_classes.master_workout_id` and the rule in
   `scheduled_classes.day_workout_id`. Everything that reads a class's WOD
   (members, bookings, drafts and missing-WOD alerts, executions, results,
   leaderboards) keeps working unchanged. `workout_source` (`day` | `class` |
   null) is derived from the two columns.
3. **Precedence** (`Scheduling.Domain.DayWorkoutInheritance`, pure): the
   class's own WOD (set on the class or its series, or edited for it) beats
   every rule; a class-type rule beats an all-types rule; a branch rule beats an
   all-branches rule of the same kind. An all-types rule covers only `class`
   kinds; an event follows a day WOD only by its own type.
4. **Override and reset.** Any explicit change of a class's WOD (the class
   form, `PUT …/slots/:id/workout`, publishing a class-specific edit,
   per-member class programming) clears `day_workout_id`: the class now has its
   own WOD. `POST …/slots/:id/day-workout` («Επαναφορά στο WOD ημέρας») puts
   the covering rule back. Removing a class's own WOD re-inherits the day's.
5. **When inheritance is applied** (`Application.DayWorkouts`): setting or
   removing a rule (its date, in one transaction); creating a class or classes
   at several branches; editing or moving classes (their new dates); creating a
   series and extending one (the dates in range that have rules). Classes that
   have started never change. A standalone class people booked keeps its WOD
   as its own when its rule stops covering it (ADR-176: a booked class keeps a
   WOD).
6. **Setting a rule** may also replace the classes' own WODs in its scope
   (`replace_own`), offered after the preview lists them. Past days are
   refused (`day_in_the_past`).
7. **API.** `GET /admin/schedule/day-workouts?from&to` (≤ 62 days),
   `POST …/day-workouts/preview`, `PUT …/day-workouts`,
   `DELETE …/day-workouts/:id`, `POST …/slots/:id/day-workout`; the schedule
   window returns `day_workouts` to staff and `workout_source` /
   `day_workout_id` on each class. Capability: `manage_schedule` or
   `manage_workouts`, like linking a WOD to a class. Branch-scoped staff
   (ADR-186) set rules only for their branch and see all-branch rules.
8. **UI.** A strip under each day's header in the day and week views: the
   day's WOD(s), or a quiet «+ WOD ημέρας» on days with classes from today on.
   One line in the month grid, which opens the day. The dialog lists the day's
   rules (scope, WOD, how many classes follow it, change, remove) and edits one
   with the class form's WOD picker (suggestions, server search, «+ Νέο WOD»
   that opens the editor over the dialog and comes back filled in), «Όλα τα
   μαθήματα / Συγκεκριμένοι τύποι», a branch only when the box has several, and
   a live preview: how many classes take it, which keep their own WOD (with
   «Να πάρουν κι αυτά»), which already started. The class sheet says «Από το
   WOD ημέρας» or names the day's WOD next to the class's own with «Επαναφορά
   στο WOD ημέρας». The library's «Ανάθεση» gains a third choice, «Ημέρα».

## Rationale
Writing the inherited WOD onto the class (with its provenance) keeps one read
path for a class's WOD across ~40 call sites, so drafts, alerts, bookings and
results needed no change and cannot disagree with what members see. Resolving
at read time would have had to be threaded through all of them. The provenance
column keeps the semantics of real inheritance: later changes to the day flow
to the classes that follow it and never to those with their own WOD.

## Alternatives Considered
- **Resolve at read time** (no write to classes): pure, but every consumer of
  `master_workout_id` (executions, leaderboards, analytics, alerts) would need
  the day lookup; rejected as fragile.
- **Bulk-link only** (assign to the day's classes once, no rule): simple, but
  classes added later would not inherit, and overrides could not be told apart
  or reset; rejected.
- **Recurring day WODs** (e.g. every Monday): a WOD changes daily; a class that
  repeats already has its series WOD. Not built.

## Consequences
- Migration `20261229100000_day_workouts` (new tenant table with RLS, FK
  `scheduled_classes.day_workout_id` with `ON DELETE SET NULL (day_workout_id)`).
- Deleting a class type or branch removes its rules; classes keep their WOD as
  their own.
- Follow-up: the member-programming and quick-assign screens could suggest the
  day's WOD by default.
