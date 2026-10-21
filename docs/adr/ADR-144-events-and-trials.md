# ADR-144: Trials (and later events)
Date: 2026-10-20
Status: Accepted (trials, P2-M3; events follow in P2-M5)

## Context
Someone who doesn't train at a box should be able to try a class from its public
page, and the box should see who came and who joined (plan §5a board 6). Booking,
attendance and memberships already exist and must not learn about trials.

## Decision
1. **Own context.** `Palee.Trials` (facade, `TrialStore` and
   `TrialScheduler` ports, Ecto and Oban adapters) owns
   `scheduling_trial_policies` (one row per box, defaults all off) and
   `scheduling_trial_requests`. Rules and the lifecycle are pure domain modules
   (`TrialRules`, `TrialLifecycle`); statuses are requested, booked, declined,
   cancelled, expired, attended, no_show, converted.
2. **A trial booking is a booking.** Accepting (or asking at an auto-approval box)
   books the seat through `Scheduling.submit_auto_approved_booking_with` with
   `kind = "trial"` and allowance `none`, so capacity, rosters and attendance work
   unchanged. Each ask and accept runs under a per-box advisory lock that re-checks
   seats per class, the weekly limit and the person's limits.
3. **History survives deletions.** A request keeps `scheduled_class_id` and
   `booking_id` as plain ids (no foreign keys) plus a `class_name` snapshot, so a
   withdrawn booking or a deleted class never deletes the trial.
4. **Reactions, not coupling.** Scheduling, attendance and finance publish domain
   events (`booking_cancelled`, `attendance_recorded`, `class_cancelled`,
   `membership_activated`); `TrialReactions` updates trials. Joining the box
   within 30 days of a trial marks it converted.
5. **Scheduled steps.** `TrialStepJob` (Oban, unique per trial and step) sends the
   reminder two hours before, expires unanswered requests at class start, and
   offers the follow-up the next day at 10:00 box time.
6. **Talking to a box you're not a member of.** The visitor uses the same box
   thread staff already have (`context_type = box`, `context_id = person`), opened
   in the box's scope under personal routes `/api/boxes/:slug/conversation`. A
   SECURITY DEFINER function lists a person's box conversations across boxes. The
   web page polls; live channels stay tenant-only.
7. **Tenant data.** Both tables are declared by the Trials tenant data policy
   (purged before Finance), and are RLS-protected: the box sees its rows, the
   person sees their own at any box.

## Consequences
- Staff accept, decline and mark attendance at `/admin/trials`; owners set the
  rules at `/admin/trials/settings` (`manage_settings`).
- Trial notifications (8 types) are translated in the API's gettext catalogs and
  the web `Trials` namespace; trials also appear in the calendar feed.
- Events (P2-M5) extend this ADR with `community_events` and attendees.
