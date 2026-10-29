# ADR-223: A new WOD written in context comes back to its form; copies keep how they were written
Date: 2026-10-28
Status: Accepted

## Context
ANR (2026-10-28) created a class without a WOD, opened it and used «+ Νέο WOD».
After publishing, the WOD editor sent the coach to the schedule page, and
linking the new WOD to the class failed with
`422 no_sections` («Workout must have at least one section before
publishing»), shown as «Ελέγξτε τις επισημασμένες τιμές» in the class. Picking
an existing WOD for a class, a member or an athlete failed the same way,
although the WOD clearly had a section in its editor.

Cause: every assignment files a *copy* of the WOD (`FileWorkoutCopy`,
`ProgramUserWorkout`), made by `duplicate_workout`. The copy's draft was
rebuilt from the original's sections only; the authoring mode and the text
(`authoring_mode`, `free_text_body`, `free_text_document`, the DSL fields)
were left behind. The copy therefore defaulted to `structured`, and
publishing it checked for structured exercises, which a free-text or
text-section WOD (ADR-180) never has. The failed copy also stayed behind as a
draft in the Classes folder.

ANR's rules for «+ Νέο WOD» from inside a screen (a class, a member, a date):
publishing must bring the coach back to that exact screen, including an open
overlay form with everything typed in it, and the WOD must be assigned to the
entity that form is about.

## Decision
1. **Copies keep how they were written.** `duplicate_workout` copies the
   authoring state into the copy's columns and its `draft_data`;
   `reconstruct_draft_data` (also used to reopen a published WOD) includes it.
2. **A copy that cannot be published is deleted** (`FileWorkoutCopy.publish_copy/3`)
   and the request fails with `422 workout_not_assignable`
   `{workout_id, title, problem: no_content | incomplete_sections | invalid_details}`,
   so the message names the WOD and what to fix in its editor, in plain words,
   inside the form that tried to assign it (ADR-214).
3. **`ContextualWorkoutCreator`** (web) opens the normal WOD editor
   (`WorkoutAuthoringModes embedded`) in a dialog *over* the current screen
   instead of navigating away. The screen underneath stays mounted, so its
   forms keep their unsaved state with no serialisation. The caller passes
   `onPublished(workoutId)`, which does the assignment (link a class, fill the
   class or series form's WOD, program a member or athlete); its errors show
   in the caller's own form. Used by the class sheet's missing-WOD notice, the
   class and series forms and member/athlete programming.
4. The WOD editors no longer navigate on publish themselves; the host decides
   (`onPublished`). A page visit keeps `?return_to=` (ADR-176) for links from
   elsewhere; the session-storage class-draft handoff is removed.

## Rationale
Keeping the origin mounted is the only way to return to *any* screen,
overlays included, without each screen having to serialise and restore its
state. The copy fix is at the single place every assignment path shares, so
classes, series, members and athletes are all fixed at once.

## Alternatives Considered
- A generic "return ticket" (stash the origin's state, navigate, restore):
  every form would need its own serialisation, and overlays, popovers and
  scroll positions are easy to lose.
- Skipping the copy for class assignments: classes need their own copy in the
  day's folder (ADR-136), and members get personal versions.
