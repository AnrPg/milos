# ADR-225: A WOD is assigned to a person only when their package includes online programming or personal training
Date: 2026-10-29
Status: Accepted

## Context
ANR (2026-10-28): "assigning a wod to an athlete works if in package is
activated personal training or online programming or both".

Until now only members were checked (ADR-125: the `personal_programming`
channel with the assigned-workouts benefit, `AuthorizeMemberProgramming`).
Athletes were assigned whatever their package said, and the touchpoint
reservation (ADR-040) followed the tenant's rollout mode, so in `observe`
mode an athlete with no package at all received WODs.

## Decision
1. **One rule for every person.** Assigning a WOD to a person (athlete or
   member) needs one of two grants in their effective subscription package
   (`Palee.Finance.Domain.ProgrammingGrant`, strict
   `EntitlementPolicy.authorize_explicit/2`: no rollout leniency, no
   missing-profile pass):
   - **online programming**: channel `personal_programming` with
     `execute_assigned_workouts`;
   - **personal training**: channel `personal_training` with
     `book_pt_sessions`.
   The role never implies it.
2. **Every per-person path checks it before writing anything**
   (`Palee.Application.AuthorizeProgramming`): `AssignWorkout`,
   `UpdateAssignedWorkout` (people newly added), `AssignWorkoutToAthletes`,
   `ProgramUserWorkout` (athletes, and members in `personal` and
   `class_variant` modes). A refusal leaves no library copy behind.
   Changing a booked class's own WOD (`class_workout`) programs the class, not
   the person, and seasons (ADR-167) carry their own programme; neither is
   checked.
3. **Touchpoints are metered for online programming only.** Personal training
   includes its programme, so no coaching touchpoint is reserved for it.
4. **Refusal:** `403 programming_not_in_package` with
   `{user_id, nickname, reason}` (replaces `member_programming_not_entitled`),
   shown in plain words in the form that tried.
5. **Said up front.** The admin profile carries
   `programming: {allowed, grant, reason}` for clients. The person's
   programming schedule explains why WODs can't be assigned, closes the
   personal modes, and keeps «change it for the whole class» open for
   members.

## Rationale
One check at the application layer, shared by every path, is the only way the
rule cannot be bypassed by one screen. Using the existing finance channels
keeps the package editor as the single place where a box decides what a
client gets.

## Alternatives Considered
- Keeping athletes ungated: contradicts ANR's rule and lets the role stand in
  for a sale.
- Hiding people without the grant from pickers: staff could not tell why
  someone is missing; the profile notice and the plain refusal explain it.
