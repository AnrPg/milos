# Phase 8 Wellbeing, Injuries, Reviews, and Satisfaction
Date: 2026-06-11
Status: Planning anchor

## Purpose

This note captures two cross-cutting product domains added during Phase 8
planning: injury reporting and user reviews/ratings. Both are needed for real
analytics around safety, satisfaction, churn risk, exercise suitability, and
coaching quality.

## Architectural Direction

The existing design doc lists bounded contexts and does not include Wellbeing or
Feedback. Adding them requires an ADR and explicit approval because it extends
the architecture.

Recommended new contexts:
- `MilosTraining.Wellbeing`: injury reports, healing events, limitations.
- `MilosTraining.Feedback`: reviews, ratings, questionnaires, review targets.

These contexts should expose public APIs and publish plain PubSub events.
Analytics should consume their facts through queries or materialized views,
without other contexts owning their schemas.

## Wellbeing Context

### Goals

- Admins can report an injury for an athlete/member.
- Athletes and members can self-report an injury.
- Admins and users can mark an injury as healed.
- Active injuries appear on relevant profile/admin drill-downs.
- Healed injuries remain in history.
- Injury and limitation data can be used in analytics.

### Core Entities

#### `injury_reports`

Suggested fields:
- `id`
- `user_id`
- `reported_by_id`
- `reported_by_role`: self, admin
- `body_area`: shoulder, knee, back, wrist, ankle, hip, etc.
- `severity`: mild, moderate, severe
- `status`: active, healed
- `started_on`
- `healed_on`
- `description`
- `training_limitations`
- `tags`
- `visibility`: admin_only, user_and_admin
- timestamps

#### `injury_status_events`

Suggested fields:
- `id`
- `injury_report_id`
- `actor_id`
- `event_type`: reported, updated, marked_healed, reopened, note_added
- `payload`
- `occurred_at`

### Analytics Slices

- Active injuries by body area.
- Injury recurrence.
- Injuries by class type or workout type.
- Injury reports after specific exercise exposure.
- Injury status versus completion rate.
- Healed users returning to training.
- Injury impact on churn and attendance.
- Common limitations by package, user type, or coach.
- Injury tags versus exercise modification frequency.

### Events

- `{:injury_reported, %{user_id: ..., injury_report_id: ...}}`
- `{:injury_healed, %{user_id: ..., injury_report_id: ...}}`

Telemetry events:
- `[:milos, :injury, :reported]`
- `[:milos, :injury, :healed]`

## Feedback Context

### Goals

- Users can rate workouts with a four-sentence questionnaire.
- Users can rate exercises.
- Users can rate gym parameters.
- Users can rate private coaching parameters.
- Users can leave general reviews.
- Reviews are associated with specific target entities when applicable.
- Admins have a dedicated reviews page.
- Users have a low-prominence dedicated page showing only reviews they left.
- Review facts feed satisfaction analytics.

### Core Entities

#### `reviews`

Suggested fields:
- `id`
- `user_id`
- `target_type`: workout, execution, exercise, class_slot, gym_parameter, coaching_parameter, membership_package, app, general
- `target_id`: nullable for general or global gym reviews
- `target_snapshot`: title/name/type at time of review
- `rating`: 1-5
- `sentiment`: positive, neutral, negative, mixed
- `visibility`: admin_only, user_visible
- `body`
- `status`: open, reviewed, archived, needs_follow_up
- timestamps

#### `review_answers`

Suggested fields:
- `id`
- `review_id`
- `question_key`
- `question_text`
- `answer_text`
- `rating_value`
- timestamps

#### Optional `review_questionnaires`

Useful when questionnaires become admin-configurable.

Suggested fields:
- `id`
- `target_type`
- `version`
- `questions`
- `active`
- timestamps

### Workout Review Questionnaire

Store answers as structured rows, not one blob.

Initial four-sentence prompts:
- How well did this workout match your current ability today?
- Which part felt most useful or enjoyable?
- Which part felt too hard, painful, confusing, or unnecessary?
- What should your coach adjust next time?

### Exercise Reviews

Suggested fields or answers:
- Rating.
- Too easy, right, too hard.
- Pain/discomfort flag.
- Comment.

### Gym Parameter Reviews

Targets can include:
- Cleanliness.
- Equipment availability.
- Schedule convenience.
- Class atmosphere.
- Coach clarity.
- Value for money.

### Private Coaching Reviews

Targets can include:
- Feedback quality.
- Programming fit.
- Communication speed.
- Motivation/support.
- Progress clarity.

## Admin UX

Dedicated page: `/admin/reviews`.

Filters:
- Target type.
- Rating.
- Sentiment.
- User type.
- Package.
- Injury status.
- Workout type.
- Class type.
- Date range.
- Needs follow-up.

Admin actions:
- Drill into user, workout, class, exercise, or package.
- Mark as reviewed.
- Mark as needs follow-up.
- Add admin-only triage tags.

## User UX

Dedicated low-prominence page: `/reviews`.

Rules:
- Shows only reviews submitted by the current user.
- Group by workout/class/exercise/general.
- Editing policy should be explicit. Append-only is cleaner for audit; editable reviews are more user-friendly but need history.

## Analytics Slices

- Workout type x satisfaction.
- Exercise x pain/discomfort reports.
- Package x satisfaction.
- Class time x satisfaction.
- Coach/coaching parameter x rating.
- Injury status x workout difficulty rating.
- Member versus athlete satisfaction.
- Review sentiment x churn risk.
- Low-rating clusters by exercise, class, or package.
- Communication satisfaction x adherence.

## Events

- `{:review_submitted, %{user_id: ..., target_type: ..., target_id: ...}}`

Telemetry events:
- `[:milos, :review, :submitted]`

