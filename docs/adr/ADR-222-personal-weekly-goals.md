# ADR-222: The weekly workout goal is personal; the box sets only the streak shields
Date: 2026-10-28
Status: Accepted

## Context
Box settings › Gamification held one «Weekly workout target» for every client
of the box. Streak shields, consistency and motivation all measured each
person against that one number, so a client training twice a week for health
and an athlete on five sessions a week were judged by the same bar. The number
of shields was fixed in code (one per renewal). ANR (2026-10-28): goals must be
personal, per user, and the box settings keep only the number of shields and
when they renew.

## Decision
1. **A goal per person.** `training_goals` holds one row per person and goal
   kind (today only `weekly_workouts`, target 1–14). No row means the platform
   default (2) applies, and the API says so (`is_default: true`). The row
   records who set it last (`set_by_role` self / coach / staff, `set_by_id`)
   and in which box (`set_in_organization_id`).
2. **Who may set it.**
   - The person, always: `Εγώ › Ρυθμίσεις › Πρόγραμμα προπόνησης`
     (`GET/PUT /api/gamification/goal`). Their own choice is final until they
     change it again.
   - Their coach (active coaching relationship), from the client's profile,
     tab Προπόνηση (`GET/PUT /api/org/:slug/staff/clients/:id/training-goal`).
   - An owner/admin, or a head coach, whose `:manage_coaching` scope is `:all`,
     for any active client of the box (ADR-099/100), same route.
   - Front desk, accountants, cleaning staff, other clients: never.
   When anyone but the person sets it, the person gets `training_goal_updated`
   (coach category, in-app and push) naming who set it and to what; the
   settings card shows «Τον όρισε ο coach σου …» and stays editable.
3. **The database bounds it.** RLS on `training_goals` through the definer
   `palee_training_goal_reachable(member)`: the acting person themselves, or in
   the session's box an owner/admin of that box (the person an active member
   there), or a coach with an active coaching relationship with the person
   there. The application narrows staff further by capability scope.
4. **The box keeps the streak rules.** `gamification_settings.streak_shields`
   (0–5, default 1, 0 turns shields off) and the existing
   `streak_shield_reset_day` (1–28, or empty = each client's sign-up day).
   `weekly_workout_target` is dropped (the app is unreleased; no box relies on
   it). The completion projection reads the person's goal for the week target
   and the box's shields and renewal.

## Rationale
The goal is a personal commitment (vision §4: the member owns their data and
choices). The coach is the one person who knows the client's plan, so they may
set it, but the member keeps the last word and is always told. Owners/admins
with full coaching scope cover boxes where nobody is assigned as coach. A
separate table (not a column on `user_gamification_preferences`) lets coaches
write it without gaining the row of the person's other preferences, and leaves
room for other goal kinds (monthly volume, a lift) without a migration of the
person's preferences.

## Alternatives Considered
- **Box default plus personal override.** Rejected: ANR asked for the box to
  set only shields; a box default would bring back the one-size target.
- **Per person per box.** Rejected: one person, one streak; a second box would
  split the same week into two answers.
- **Coach-only goals** (the member cannot change them). Rejected: against the
  member's ownership; the coach is notified of nothing new, the member is.

## Consequences
- The landing payload carries `gamification.goal`; `gamification.settings`
  carries `streak_shields` instead of `weekly_workout_target`.
- Stats change on the next completion after a goal change (the projection
  runs on completion, as before).
- New notification type `training_goal_updated`.

## Implementation Notes
- Migration `20261226140000_personal_training_goals`.
- Domain: `Palee.Gamification.Domain.WeeklyGoal`; schema `TrainingGoal`;
  use cases `GetTrainingGoal`, `SetTrainingGoal`; controller
  `TrainingGoalController`.
- Web: `components/training-goal/*` (stepper, member setting, client panel),
  box settings section «Σερί, ασπίδες σερί & κατάταξη».
