# ADR-061: Semantic notifications and canonical deep links
Date: 2026-07-18
Status: Accepted

## Context

ADR-051 separates conversational Messages from passive Notifications, but some
workflow-generated text has drifted into Messaging. In particular, an athlete's
workout-assignment request creates a direct chat message, even though it is a
workflow event that requires admin action. Review submissions only invalidate
the admin review read model and create no notification.

Notification payloads also retain route names and query parameters from older
admin pages. The inbox currently translates `/schedule` to `/admin/schedule`
and assignment links to `open`, while the canonical navigation surfaces are
`/admin/class-schedule` and `/admin/coaching-assignments?open_assignment=...`.
As a result, click-through can open the wrong surface or fail to select the
relevant record.

## Decision

User-authored conversation remains in Messaging only when its intent is a
person-to-person exchange. Workflow-generated actionable text is persisted as
a semantic Notification, even when it contains a user-authored note.

Add dedicated `workout_assignment_requested` and `review_submitted`
notification types. Workout-assignment requests no longer create direct chat
messages. Their notification links open Personal Coaching on the requested
date. Review notifications open the admin Reviews surface.

Notification producers own semantic destination data. A small frontend route
normalizer preserves compatibility with already-persisted legacy URLs and maps
them to current canonical routes and query names. The Notifications and
Messages controls retain independent unread counters; only incoming chat
threads contribute to the Messages counter.

## Rationale

The distinction follows user intent and lifecycle rather than whether a payload
contains text. Assignment requests, booking decisions, execution annotations,
class-related administrative notes, and reviews are state-change signals that
need triage and deep-link navigation. Direct chat is an ongoing conversation.

Dedicated semantic types keep presentation, filtering, push copy, analytics,
and destinations explicit. Compatibility normalization repairs historical
records without rewriting notification payloads in place.

## Alternatives Considered

Keeping assignment requests as chat and linking the thread to Personal
Coaching was rejected because it makes an actionable workflow event increment
the Messages badge and hides it among conversations.

Using the generic `athlete_message` notification type was rejected because it
does not distinguish assignment demand from freeform athlete communication and
cannot provide stable event-specific copy or routing.

Rewriting existing notification payloads in a data migration was rejected
because route normalization can safely support both legacy and canonical links
without mutating user history.

## Consequences

Notification type additions must remain aligned across the database
constraint, Ecto enum, event dispatcher, push builder, frontend presentation,
and tests, as tracked by TD-023.

The workout-assignment request endpoint now reports notified admins after
enqueueing notification delivery rather than after creating chat messages.
Messages counters no longer include those requests.

## Implementation Notes

Implemented dedicated `workout_assignment_requested` and `review_submitted`
types across the database constraint, Ecto enum, durable event dispatcher,
localized push-message builder, inbox presentation, and regression tests.

Workout-assignment requests now enqueue one Notifications-owned semantic event
with a per-request idempotency key and no longer create direct Messaging
threads. The Personal Coaching link carries the requested date so the calendar
opens on the relevant period. Review submissions notify admins after the
Feedback write succeeds and link to `/admin/reviews`.

Added a tested frontend compatibility normalizer for previously persisted
`/my-workouts?...open=...` and `/admin/schedule` destinations. New assignment
links use `open_assignment`, schedule links use `open_slot`, and the canonical
admin surfaces are `/admin/coaching-assignments` and
`/admin/class-schedule`. The assignment console accepts both legacy and current
query names during the transition.

The top navigation now uses a bell glyph for Notifications and retains the
Notifications unread badge separately from the incoming-thread Messages badge.
No new technical debt was deferred; TD-023 continues to track replacement of
the manually synchronized notification-type contract.
