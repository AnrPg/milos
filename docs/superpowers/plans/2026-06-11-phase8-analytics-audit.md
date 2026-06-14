# Phase 8 Analytics Audit
Date: 2026-06-11
Status: Planning anchor

## Purpose

This note anchors the analytics audit discussion for Phase 8. The goal is to
make future implementation work explicit: analytics cannot report real values
unless the app persists the underlying domain facts, emits telemetry at write
boundaries, and refreshes materialized read models from those facts.

Use this as the checklist for deciding what needs to be added before the admin
dashboard claims support for a slice.

## Verbatim Audit Answer

**Audit Principle**
For analytics, the app needs three layers of data:

- **Authoritative tables:** memberships, bookings, workouts, executions, notes, reviews, injuries, payments.
- **Derived read models:** `finance_aggregates`, `coaching_aggregates`, maybe `engagement_aggregates`, refreshed by Oban.
- **Telemetry/event facts:** timestamped events for things that are not naturally stored as state, like notification click-through, message response latency, view/open events, push delivery outcomes, assignment opened, workout started, workout abandoned.

Current app has strong foundations for workouts, scheduling, executions, gamification, notifications, and coaching notes. It does not yet have finance, reviews, injuries, attendance/no-show tracking, communication threads, or domain telemetry facts.

**Finance**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `user_type` | Identity role exists; finance snapshot missing | Add `memberships.user_type_snapshot`; update on membership create/admin edit |
| `identity_role` | Already in `users.role` | Join from Identity; monitor role changes as finance/user-index refresh triggers |
| `membership_status` | Missing | Add membership lifecycle status and status history events |
| `package_code` | Missing | Add `membership_packages.code` and package subscriptions |
| `package_family` | Missing | Add package family field/taxonomy |
| `billing_period` | Missing | Add package billing period and subscription snapshot |
| `price_band` | Missing | Derived from package/payment amount; define configurable thresholds |
| `package_tags` | Missing | Add package tags table or array field; index in Meilisearch |
| `package_parameters` | Missing | Add structured `params` map on packages plus snapshot on subscriptions |
| `promotion_campaign_id` | Missing | Add promotion campaigns and redemptions |
| `promotion_code` | Missing | Add concrete promo codes and redemption records |
| `discount_type` | Missing | Add discount type/value on campaign/code/redemption |
| `referral_program_id` | Missing | Add referral programs and referral events |
| `referrer_user_id` | Missing | Add referral event linking referrer and referred user |
| `referral_status` | Missing | Add referral event/reward status lifecycle |
| `signup_source` | Missing | Add membership/user acquisition source at registration or admin-create |
| `payment_method` | Missing | Add payment records with method |
| `payment_status` | Missing | Add payment status: paid, pending, refunded, failed, waived |
| `cohort_month` | Missing | Derived from membership `starts_on` or user `inserted_at`; persist in aggregate |
| `expires_within_days` | Missing | Derived from `memberships.expires_on`; refresh daily and on membership writes |
| `renewal_count` | Missing | Derived from payment/subscription renewal events |
| `churn_risk_bucket` | Missing | Derived from expired/payment overdue/inactivity; needs finance + workouts/classes joins |
| `training_type_affinity` | Partially derivable from bookings/executions | Add aggregate job counting class/workout types by user |
| `location_or_channel` | Missing | Add package/member channel: in-person, remote, hybrid |

**Workouts**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `workout_type` | Stored on `master_workouts.type` | Include in aggregates |
| `workout_format` | Partially implicit in timer/score config | Add explicit `format` or normalized section/workout format |
| `workout_status` | Draft/published exists; assigned/rejected/completed distributed | Build derived status from master workouts, assignments, executions, rejections |
| `source` | Stored on executions | Include in execution aggregates |
| `scale_level` | Stored through scale levels and execution input | Persist selected scale on execution if not already stable enough |
| `program_track` | Missing | Add track to workouts/assignments/user profile |
| `coach/admin_created_by` | Workouts have created_by | Add coach assignment where needed; aggregate by creator/assigned coach |
| `scheduled_day/time/season` | Derivable from slots/assigned workouts | Materialize time buckets in aggregates |
| `completion_time_bucket` | Partially derivable | Compare scheduled date/time to completed time; persist derived bucket |
| `rejection_reason/category` | Rejection exists with messages | Add structured reason/category field instead of free text only |

**Progress**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `completion_rate` | Derivable from assignments/classes/executions | Need denominator rules: assigned, booked, self-selected; aggregate by period |
| `streak_bucket` | User stats exist | Bucket from gamification stats |
| `PR_count/type/frequency` | Gamification achievements/PR logic exists | Ensure PR facts store score type, section/exercise, date |
| `score_type` | Score config exists | Persist normalized score type on completed score facts |
| `score_delta` | Missing derived metric | Compare current score to prior best/recent baseline |
| `consistency_bucket` | Partially from streak target | Add weekly adherence aggregate |
| `training_frequency` | Derivable from executions/classes | Aggregate sessions per week/month |
| `time_to_completion` | Execution elapsed snapshots exist | Compare planned/timer duration to actual elapsed |
| `modification_frequency` | Exercise notes/progress exist partially | Track substitutions, skipped exercises, changed loads/reps as structured events |
| `note_frequency` | Execution notes exist | Aggregate notes per workout/user/period |
| `challenge_progress` | Gamification challenge progress exists | Add active/completed/stalled buckets |
| `leaderboard_opt_in` | Exists | Join from gamification opt-in |

**Classes**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `class_type` | Stored on scheduled class | Include in aggregates |
| `slot_time` | Derivable | Add time bucket function |
| `day_of_week` | Derivable | Add date bucket function |
| `capacity_bucket` | Approved booking count exists | Compare approved count to capacity |
| `booking_status` | Exists: pending/approved/rejected/withdrawn likely | Aggregate booking transitions |
| `approval_mode` | Slot auto_approve exists | Persist/aggregate from slot |
| `booking_lead_time` | Derivable from booking inserted_at vs class time | Add bucket calculation |
| `waitlist_status` | Missing | Add waitlist tables/events if needed later |
| `attendance_status` | Missing | Add class attendance check-in/no-show/cancel status |
| `coach` | Missing on slots unless implicit admin | Add coach_id to scheduled classes |
| `location/room` | Missing | Add room/location entity or field |
| `class_series/template` | Missing | Add recurring class template if recurring scheduling matters |
| `late-cancel/no-show` | Missing | Requires cancellation deadlines and attendance records |

**Athletes**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `athlete_status` | Assignment status exists, profile status missing | Add athlete profile status or derive from activity |
| `remote_vs_in_person` | Missing | Add channel to membership/profile/packages |
| `package_code/family/status` | Missing finance context | Join from Finance |
| `goal_type` | Missing | Add athlete/member profile goals |
| `experience_level` | Missing | Add profile field |
| `injury_or_limitation_tags` | Missing | Add Wellbeing injury reports and active limitations |
| `preferred_training_days` | Missing | Add profile preferences |
| `preferred_training_type` | Missing | Add profile preferences |
| `coach_assigned` | Missing | Add coach assignment relation |
| `engagement_bucket` | Missing derived metric | Aggregate login/activity/execution/message signals |
| `last_active/days_since` | Partially derivable from executions/bookings | Add user activity facts for meaningful last active |
| `response_latency_to_coach` | Missing | Requires communication threads/messages with timestamps |
| `assignment_acceptance_rate` | Partially from assigned workout athlete status | Need accepted/opened/skipped/rejected lifecycle, not just rejected |

**Exercises**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `exercise_name` | Stored on workout exercises | Include in aggregates |
| `movement_pattern` | Missing | Add exercise catalog metadata |
| `equipment` | Missing | Add exercise catalog metadata |
| `muscle_group` | Missing | Add exercise catalog metadata |
| `skill_domain` | Missing | Add exercise catalog metadata |
| `load_mode` | Stored | Aggregate from exercise prescription |
| `prescription_unit` | Stored | Aggregate from prescription |
| `scale_variant_used` | Partially available from scale materialization | Persist actual selected variation per execution |
| `exercise_modification_rate` | Missing structured data | Track skipped/modified/substituted/load-changed per exercise |
| `exercise_note_tags` | Notes support tags in payload/UI partially | Normalize tags into queryable fields |
| `PR_exercise` | PR detection likely section-based | Add exercise-level PR facts if needed |
| `movement_exposure_frequency` | Requires exercise metadata | Count completed exposure by movement pattern/equipment/etc. |
| `movement_progression_level` | Missing | Add catalog progression fields or per-user movement level snapshots |

**Satisfaction**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `post_workout_rating` | Missing | Add Feedback reviews targeted to execution/workout |
| `session_rpe` | Missing | Add post-workout questionnaire answer |
| `mood_before/after` | Missing | Add pre/post check-in or review answers |
| `pain_or_discomfort_flag` | Missing | Add review answer and/or injury report shortcut |
| `workout_enjoyment` | Missing | Add workout review questionnaire |
| `program_satisfaction` | Missing | Add reviews targeting program/package/coach |
| `coach_satisfaction` | Missing | Add reviews targeting coach/private coaching |
| `class_satisfaction` | Missing | Add reviews targeting scheduled class |
| `difficulty_fit` | Missing | Add structured answer: too easy/right/too hard |
| `free_text_feedback_tags` | Missing | Add manual/admin tags or controlled user tags |
| `nps_bucket` | Missing | Add NPS-style review later |
| `complaint/positive_category` | Missing | Add review categories and admin triage fields |

**Communication**
| Dimension | Current State | Needed Tracking |
|---|---|---|
| `message_direction` | Some message endpoints exist, no durable thread model seen | Add communication messages table with sender/recipient |
| `message_context` | Payloads have context sometimes | Add structured context_type/context_id |
| `sender_role/recipient_role` | Derivable from users at send time | Store role snapshots on messages |
| `response_time_bucket` | Missing | Requires threads and reply-to relationship |
| `unanswered_message_age` | Missing | Requires open thread state and last inbound/outbound timestamps |
| `thread_status` | Missing | Add thread status: open/resolved/needs_follow_up |
| `communication_channel` | Partial: notifications/push exist | Add channel field for in-app/push/email/SMS |
| `notification_type` | Stored | Already usable |
| `notification_read_status` | Stored via `read_at` | Already usable |
| `notification_clickthrough_status` | Missing | Add `notification_click_events` or `clicked_at` per notification |
| `push_delivery_status` | Missing | Add push dispatch attempt table/status from Oban job results |
| `coach_note_type` | Missing | Add structured note type to coaching notes |
| `communication_frequency` | Derivable after message/thread persistence | Aggregate by user/coach/context/period |
| `sentiment_tag` | Missing | Add manual tags; avoid automatic sentiment until explicitly desired |

**Monitoring Needed**
I would add a small internal analytics event pipeline, but only for events that are not already authoritative DB state.

Persisted event/fact tables needed:
- `analytics_events` or context-specific fact tables for `page_view`, `entity_opened`, `workout_started`, `workout_abandoned`, `notification_clicked`, `push_attempted`, `push_delivered_or_failed`, `message_sent`, `thread_resolved`.
- `attendance_records` for class attendance/no-show.
- `review_answers` and `reviews` for satisfaction.
- `injury_reports` and `injury_status_events` for injuries/healing.
- `exercise_catalog` metadata for movement/equipment/muscle-group analytics.
- `communication_threads` and `communication_messages` for response latency and unresolved communication.

Telemetry events to emit:
- `[:milos, :workout, :started]`
- `[:milos, :workout, :completed]`
- `[:milos, :workout, :abandoned]`
- `[:milos, :booking, :submitted]`
- `[:milos, :booking, :resolved]`
- `[:milos, :class, :attendance_marked]`
- `[:milos, :notification, :read]`
- `[:milos, :notification, :clicked]`
- `[:milos, :push, :dispatch_result]`
- `[:milos, :message, :sent]`
- `[:milos, :review, :submitted]`
- `[:milos, :injury, :reported]`
- `[:milos, :injury, :healed]`
- `[:milos, :membership, :renewed]`
- `[:milos, :payment, :recorded]`
- `[:milos, :referral, :status_changed]`

The practical Phase 8 approach is: store domain facts in their owning contexts, emit telemetry at write boundaries, and build `finance_aggregates`, `coaching_aggregates`, and probably `engagement_aggregates` from those facts. Telemetry alone is not enough for analytics unless it is also persisted or exported to a metrics store; for this self-hosted app, persisted event facts plus materialized views are the safer default.

