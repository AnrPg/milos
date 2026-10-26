# ADR-201: WOD variation for several people at once
Date: 2026-10-26
Status: Accepted

## Context
A coach programs a workout for one member or athlete at a time, from that
person's admin profile (`ProgramUserWorkout`, ADR-071, ADR-125, ADR-136).
Members get one of three modes: `class_workout`, `class_variant` (their own
version of a class they booked) or `personal`. Athletes get a personal
assignment. Coaches often want the same scaled version for several people in
one class, and doing it one profile at a time is slow.

The product owner said: «treat every one from the list as if it was the sole
one and continue using code as is today».

## Decision
1. **One new endpoint, no new programming rules.**
   `POST /api/org/:slug/admin/users/programming` takes `user_ids` plus the
   same params as `POST /users/:id/programming`. A new application use case,
   `Palee.Application.ProgramWorkoutForUsers`, calls
   `ProgramUserWorkout.call/4` once per person, with the same params, exactly
   as for one person. So each person gets their own copy, filed in their own
   folder, after the same mode, booked-class and personal-programming checks.
2. **The same client check, per person.** The one-person route refuses a
   coach whose scope is `:own` for anyone who is not their client
   (`not_your_client`, ADR-100). The new route has no person in its path, so
   the use case runs `AuthorizeClientAccess` with `:manage_coaching` for each
   person before programming them. The route itself needs `:manage_coaching`
   (`RouteCapabilities`).
3. **Results per person, no rollback.** The answer is
   `results: [%{user_id, status: "ok", mode, workout, association} |
   %{user_id, status: "error", code, params?}]`, in request order. The
   `code` and `params` are the ones the one-person endpoint would answer, so
   the web localizes them with the existing error keys. One person failing
   never undoes the others.
4. **Bounds.** Ids are deduplicated, first occurrence first. The list holds 1
   to 50 people: the OpenAPI schema refuses an empty list or one longer than
   50, and the use case answers `invalid_user_ids` / `too_many_users` (422)
   on its own as well.
5. **Two entry points on the web.**
   - The class popup (staff with `manage_coaching`) gets «Variation for…» /
     «Παραλλαγή για…». It lists the class's attendees (approved and pending
     bookings, each person once, guest bookings left out, and a hint on those
     who already have a version). Staff tick people, pick the WOD to start
     from (the class's own WOD by default) and each one gets a `class_variant`.
   - The profile programming dialog gets a collapsed «Also for…» picker. It
     is not offered in the `class_workout` mode, since replacing the class's
     workout already reaches everyone. When the coach has just written or
     edited a WOD (`copy_source: false`), the profile's person gets that WOD
     as today and the others each get a copy.
   Both show the outcome per person: who got it, and the localized reason for
   those who did not.

## Rationale
Looping over the existing use case keeps one place for the programming rules,
as the owner asked. Every check, folder rule and library-visibility rule
(ADR-125, ADR-136) applies unchanged, and a fix to `ProgramUserWorkout` fixes
both paths. Results per person, instead of one transaction for everyone, match
how staff work: a member whose package lacks personal programming should not
stop the rest of the class from getting their version.

## Alternatives Considered
- **One shared copy for the whole group.** Fewer workouts in the library, but
  a later edit for one person would change it for everyone. It also breaks
  the "own copy, own folder" rule of ADR-125/136. Rejected.
- **All or nothing (one transaction).** One person without the grant would
  block the whole class. The owner asked for "as if each were alone".
  Rejected.
- **Looping in the browser over the one-person endpoint.** No API change, but
  50 round trips, no server-side cap, and a half-done result if the tab
  closes. Rejected.
- **Assigning several people through `AssignWorkout` with `source_slot_id`.**
  A class variant is single-member by design
  (`class_variant_requires_single_member`). Rejected.

## Consequences
- A group of N people writes N workout copies and N assignments. The cap of
  50 bounds one request.
- The request runs one person after another inside a single HTTP call. At 50
  people this takes a few seconds; that is acceptable for a staff action.
- An athlete who booked a class and is picked in «Variation for…» gets a
  personal assignment, because that is what `ProgramUserWorkout` does for
  athletes.

## Implementation Notes
- API: `apps/api/lib/palee/application/program_workout_for_users.ex`,
  `AdminUserController.program_workout_for_users/2`, route
  `post "/users/programming"`, and a FallbackController clause for the two
  422 codes. Tests:
  `apps/api/test/palee_web/controllers/group_wod_variations_controller_test.exs`.
- Web: `src/lib/group-variations.ts` (pure rules, vitest),
  `components/schedule/ClassVariationDialog.tsx`,
  `components/admin/users/AdditionalPeoplePicker.tsx`,
  `components/workouts/GroupOutcomeList.tsx`, and the e2e spec
  `e2e/group-wod-variations.spec.ts`.
- `not_your_client` now has a localized message in `API_ERROR_KEYS`
  (`rhErrNotYourClient`).
- A class variant's day is the class's UTC date, because the API checks the
  booking within that UTC day.
