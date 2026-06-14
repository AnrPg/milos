# Phase 8 Analytics Dimensions and Slices
Date: 2026-06-11
Status: Planning anchor

## Purpose

This note captures the slice catalog discussed before the analytics audit. It is
the vocabulary the admin dashboard, search index, aggregate views, and future
filters should converge on. Not every dimension must ship in the first Phase 8
implementation, but schema and indexes should avoid choices that make these
dimensions impossible later.

## Finance and Coaching Dimensions

- `user_type`: member, athlete, admin-excluded.
- `identity_role`: current Identity role, separate from finance `user_type_snapshot`.
- `membership_status`: active, expiring, expired, cancelled, paused, trial, comped.
- `package_code`: specific membership package code.
- `package_family`: unlimited, limited-visits, personal-programming, hybrid.
- `billing_period`: monthly, quarterly, annual, custom.
- `price_band`: free/comped, low, mid, high, custom.
- `package_tags`: crossfit, open-gym, remote, student, family, custom admin tags.
- `package_parameters`: `visits_per_week`, `includes_remote_programming`, `includes_classes`, `coaching_touchpoints_per_month`, and future structured package values.
- `promotion_campaign_id`: campaign that influenced signup, renewal, or revenue.
- `promotion_code`: concrete code used.
- `discount_type`: percent, fixed amount, free period, manual.
- `referral_program_id`: referral program that produced the signup or reward.
- `referrer_user_id`: revenue or signup attributable to a user.
- `referral_status`: pending, approved, applied, rejected.
- `signup_source`: direct, referral, promo, admin-created, migrated/imported.
- `payment_method`: cash, bank transfer, card/manual, other.
- `payment_status`: paid, pending, refunded, failed, waived.
- `membership_start_month` / `cohort_month`: cohort analysis.
- `expires_within_days`: operational expiring-soon filters.
- `renewal_count`: first-time, renewed once, repeat.
- `churn_risk_bucket`: expired recently, inactive workouts/classes, payment overdue.
- `training_type_affinity`: inferred from bookings and executions.
- `location_or_channel`: in-person, remote, hybrid.

## Gym Member Dimensions

Gym members need their own analytics slices. They are not just non-athletes.

- `member_status`: active, expiring, expired, cancelled, paused, trial.
- `membership_package`: class pack, unlimited, limited visits, student, family, hybrid.
- `class_attendance_rate`: booked versus attended.
- `booking_behavior`: early booker, same-day booker, late canceller, frequent pending bookings.
- `class_type_preference`: CrossFit, strength, gymnastics, aerobics, flexibility, recovery.
- `time_slot_preference`: morning, noon, evening, weekend.
- `capacity_pressure`: how often they book high-demand or full classes.
- `no_show_rate`: after attendance records exist.
- `withdrawal_rate`: booked then cancelled or withdrew.
- `approval_outcome`: approved, rejected, pending history.
- `member_retention_cohort`: joined month, package, promo, referral source.
- `member_engagement_bucket`: frequent, regular, occasional, inactive.
- `injury_status`: currently injured, recently healed, recurring injury.
- `satisfaction_bucket`: class, gym, workout, or package satisfaction.
- `communication_status`: unread admin messages, unresolved threads, response delay.

Useful admin questions:
- Which class packages retain best?
- Which time slots are overloaded?
- Which members are silently disengaging?
- Are injured members still booking risky classes?
- Do certain class types produce lower satisfaction?

## Workouts

- `workout_type`: CrossFit, strength, gymnastics, aerobics, flexibility, recovery.
- `workout_format`: AMRAP, EMOM, for time, strength sets, intervals, recovery.
- `workout_status`: draft, published, assigned, completed, rejected, skipped.
- `source`: class booking, assigned workout, self-selected.
- `scale_level`: beginner, intermediate, advanced, or scaled/Rx/Rx+.
- `program_track`: general fitness, competition prep, strength block, rehab, remote coaching.
- `coach/admin_created_by`.
- `scheduled_day_of_week`, `scheduled_time_bucket`, `season/month`.
- `completion_time_bucket`: same day, late, early.
- `rejection_reason` or rejection message category.

## Progress

- `completion_rate`: per athlete, package, workout type, coach, and time period.
- `streak_bucket`: none, 1-2 weeks, 3-6 weeks, 7+ weeks.
- `PR_count`, `PR_type`, `PR_frequency`.
- `score_type`: time, reps, load, rounds, distance, calories, HRR.
- `score_delta`: improved, flat, regressed.
- `consistency_bucket`: weekly target met, partial, missed.
- `training_frequency`: sessions per week.
- `time_to_completion`: planned versus actual elapsed duration.
- `modification_frequency`: how often athletes modify prescribed work.
- `note_frequency`: how often athletes annotate workouts.
- `challenge_progress`: active, completed, stalled.
- `leaderboard_opt_in`: yes/no.

## Classes

- `class_type`: CrossFit, strength, gymnastics, aerobics, flexibility, recovery.
- `slot_time`: morning, noon, evening.
- `day_of_week`.
- `capacity_bucket`: empty, low, healthy, full.
- `booking_status`: pending, approved, rejected, withdrawn, no-show if added.
- `approval_mode`: auto-approved versus coach-approved.
- `booking_lead_time`: booked early, same day, late.
- `waitlist_status`: if added later.
- `attendance_status`: attended, missed, cancelled, late-cancel.
- `coach`.
- `location/room`: if added later.
- `class_series` or recurring template: if added later.

## Athletes

- `athlete_status`: active, inactive, paused, churn-risk, onboarding.
- `remote_vs_in_person`: remote, in-person, hybrid.
- `package_code`, `package_family`, `membership_status`.
- `goal_type`: strength, weight loss, competition, mobility, general fitness, rehab.
- `experience_level`.
- `injury_or_limitation_tags`.
- `preferred_training_days`.
- `preferred_training_type`.
- `coach_assigned`.
- `engagement_bucket`: high, medium, low.
- `last_active_at`, `days_since_last_workout`.
- `response_latency_to_coach`.
- `assignment_acceptance_rate`.

## Exercises

- `exercise_name`.
- `movement_pattern`: squat, hinge, push, pull, carry, locomotion, core.
- `equipment`: barbell, dumbbell, kettlebell, bodyweight, machine, cardio.
- `muscle_group`.
- `skill_domain`: strength, gymnastics, conditioning, mobility.
- `load_mode`: bodyweight, percentage, RPE, fixed load.
- `prescription_unit`: reps, time, distance, calories, meters.
- `scale_variant_used`.
- `exercise_modification_rate`.
- `exercise_note_tags`: pain, too easy, too hard, form, equipment, fatigue.
- `PR_exercise`.
- `movement_exposure_frequency`.
- `movement_progression_level`.

## Satisfaction

Satisfaction needs explicit capture. It cannot be treated as reliable analytics
if it is only inferred from usage.

- `post_workout_rating`: 1-5 or simple easy/ok/hard.
- `session_rpe`.
- `mood_before`, `mood_after`.
- `pain_or_discomfort_flag`.
- `workout_enjoyment`.
- `program_satisfaction`.
- `coach_satisfaction`.
- `class_satisfaction`.
- `difficulty_fit`: too easy, right, too hard.
- `free_text_feedback_tags`.
- `nps_bucket`: if added later.
- `complaint_category`.
- `positive_feedback_category`.

## Communication

- `message_direction`: athlete-to-admin, admin-to-athlete, member-to-admin, admin-to-member.
- `message_context`: assigned workout, class slot, coaching note, general.
- `sender_role`, `recipient_role`.
- `response_time_bucket`.
- `unanswered_message_age`.
- `thread_status`: open, resolved, needs follow-up.
- `communication_channel`: in-app, push, future email/SMS.
- `notification_type`.
- `notification_read_status`.
- `notification_clickthrough_status`.
- `push_delivery_status`: if delivery receipts are modeled later.
- `coach_note_type`: instruction, encouragement, correction, follow-up, admin.
- `communication_frequency`.
- `sentiment_tag`: if manually tagged later.

## High-Value Cross Cuts

- Package x completion rate.
- Package x class attendance.
- Package x churn risk.
- Coach x athlete progress.
- Workout type x satisfaction.
- Exercise x modification or pain notes.
- Time slot x booking or attendance.
- Scale level x completion or PR rate.
- Referral source x retention or progress.
- Promotion campaign x retention, not only revenue.
- Communication latency x athlete adherence.
- Coach notes x subsequent completion rate.
- Satisfaction x churn risk.
- Injury tags x exercise modification frequency.

## Suggested Phase 8 v1 Filters

- `q`
- `user_type`
- `identity_role`
- `membership_status`
- `package_code`
- `package_tag`
- `promotion_campaign_id`
- `referral_program_id`
- `expires_within_days`
- `workout_type`
- `scale_level`
- `completion_rate_bucket`
- `last_active_bucket`
- `class_time_bucket`
- `coach_assigned`
- `injury_status`
- `satisfaction_bucket`
- `communication_status`

