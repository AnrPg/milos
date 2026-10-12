# ADR-096: Self-organising workout library and workout icons
Date: 2026-10-13
Status: Accepted

## Context
Coaches program workouts in three ways: build them in the library and assign
them later, program them from an athlete's profile, or attach them to classes.
The library was a flat list of whatever was created, so it became hard to find
what a given athlete or class actually received. Coaches also asked for a
file-explorer feel, with an icon per workout that tells them at a glance what
kind of session it is.

## Decision
1. **System folders.** Folders carry an optional `system_key`. The app keeps
   `Athletes/<athlete>` (`athletes`, `athlete:<user id>`) and
   `Classes/<yyyy>/<mm>/<yyyy-mm-dd>` (`classes`, `classes:<yyyy>`,
   `classes:<yyyy-mm>`, `classes:<yyyy-mm-dd>`). They are found by key, so
   coaches can rename, move or nest them; deleted ones are recreated on demand.
   `Athletes`, `Classes` and one folder per active athlete are ensured when the
   library is listed. Year, month and day folders are created only when a
   workout is first assigned to a class on that date, never for merely
   scheduling a class, so the Classes tree does not fill up with empty days.
2. **Filing by copy.** Assigning a library workout to an athlete gives each
   athlete their own published copy in their folder. Assigning one to a class
   files a copy in the class's gym-local day folder; classes on the same day
   share that copy. A workout already in the target folder is used as-is.
   Templates are never modified. Copies keep the original's title and icon.
3. **Icons.** `master_workouts.icon` holds one emoji, validated as a single
   grapheme. `icon_source` is `coach` (picked by hand, never overwritten) or
   `ai`. With no stored icon the web app uses keyword rules (English and
   Greek) on the title, then the workout type. Folders always use rules.
4. **AI suggestion (optional).** After every publish, a background job
   (`SuggestWorkoutIconJob`) asks Google Gemini for one emoji through the
   `WorkoutIconSuggester` port. It runs only when `GEMINI_API_KEY` is set
   (`GEMINI_MODEL` selects the model) and sends only the workout's title,
   type, description and section/movement names. Failures are silent and
   publishing never waits on it.

## Rationale
Keys rather than names make the structure robust to coaches reorganising it.
Copies match how coaches think ("Maria's Monday WOD") and let them personalise
a workout without touching the template or other athletes. Rules give every
file a sensible icon immediately and with no external dependency; AI only
refines it.

## Alternatives Considered
- *Virtual folders computed from assignments*: no per-athlete personalisation,
  and coaches could not restructure them.
- *Multiple folder links per workout*: needs a join table and makes edits
  affect every athlete at once.
- *Creating every day folder when classes are scheduled*: rejected, because
  recurring schedules would create hundreds of empty folders.
- *Calling the model synchronously on publish*: adds latency and an external
  failure mode to a core action.

## Consequences
- One assignment per athlete, where previously one assignment could cover
  several athletes. If a later athlete fails (for example, no programming
  allowance), earlier athletes keep their assignment.
- Recurring series keep referencing their template. A day is filed when a
  coach assigns that day's workout.
- Root folder names became unique per organization (they were unique
  globally).
- Gemini is an external, optional processor of workout titles and content.
  Deployments that must stay fully self-hosted leave `GEMINI_API_KEY` unset.

## Implementation Notes
- `WorkoutLibraryFolders`, `FileWorkoutCopy`, `ClassWorkoutFiling`,
  `AssignWorkoutToAthletes`, `SuggestWorkoutIcon`, `SetWorkoutIcon` (application
  layer); `GeminiWorkoutIconSuggester` (infrastructure).
- Class dates use the organization's timezone setting (UTC by default).
