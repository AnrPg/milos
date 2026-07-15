# ADR-025: Admin Search, Communication, Attendance, and Calendar Export Foundations
Date: 2026-06-13
Status: Accepted

## Context

Phase 8 added finance, analytics, communication, wellbeing, and feedback foundations, but several feature surfaces still rely on provisional boundaries:

- Admin member search is PostgreSQL-backed and filters some Finance dimensions after loading a limited set of summaries, so package-filtered results can be incomplete and there is no live suggestion index.
- Communication thread/message tables exist, but existing schedule, workout, and coaching message flows do not consistently write durable communication records for analytics and response-latency reporting.
- Attendance facts are currently stored in Analytics projection tables instead of being owned first by Scheduling/Workouts and then projected into Analytics.
- Members and athletes cannot subscribe to schedule or assigned-workout feeds from external calendar apps.

These are structural concerns because they affect context ownership, read-model semantics, and external feed security.

## Decision

Implement these foundations additively and preserve the existing user-facing APIs where possible:

1. **Admin search** uses a Meilisearch-backed member index as the primary query adapter. PostgreSQL remains a correctness fallback when Meilisearch is unavailable or returns an error. Meilisearch documents are denormalized read models only; Identity, Finance, Wellbeing, Feedback, Analytics, and Coaching remain the sources of truth.
2. **Communication durability** is written through public Analytics APIs from schedule, workout, and coaching application services. Existing compatibility tables can remain during migration, but durable communication threads/messages become the analytics source for communication dimensions.
3. **Attendance ownership** moves to a source-fact table owned by Scheduling. Analytics attendance records become projections derived from Scheduling-owned attendance facts, not the canonical write target.
4. **Calendar export** uses signed per-user feed tokens. UI pages expose a `webcal://` subscribe link, an `https://...ics` copy link, and a one-off download action. Feed endpoints are unauthenticated but require a valid signed token and never expose another user's schedule without token verification.

## Rationale

Meilisearch is the correct adapter for live admin suggestions and multi-dimensional member search because the planned slices combine identity, finance, wellbeing, satisfaction, communication, and engagement facets that should not be joined ad hoc by controllers. Keeping PostgreSQL fallback preserves operational correctness when the search daemon is down.

Durable communication records should be emitted at existing write boundaries instead of reconstructed later from logs or UI state. This keeps analytics facts close to the action that created them and avoids a second telemetry-only pathway for important business events.

Attendance is a source fact of scheduled class participation, so Scheduling must own it. Analytics should project and aggregate attendance rather than being the initial persistence boundary.

Calendar feeds need stable URLs that work in Google Calendar, Apple Calendar, Outlook, and direct `.ics` downloads. Signed feed tokens avoid requiring external calendar clients to send JWT headers while still preventing open enumeration.

## Alternatives Considered

1. **Keep PostgreSQL-only admin search**: rejected because it preserves the current incomplete filtering/pagination behavior and does not support live, denormalized suggestions.
2. **Make Meilisearch the source of truth**: rejected because it would violate bounded context ownership and make search availability part of write correctness.
3. **Store communication only in existing assignment-message tables**: rejected because schedule and coaching flows need one analytics-compatible thread model, and assignment messages alone cannot represent all communication contexts.
4. **Leave attendance in Analytics and add more validations**: rejected because it keeps a projection table as the canonical source fact.
5. **Require authenticated calendar API calls**: rejected for subscription feeds because common calendar clients cannot attach bearer tokens. Signed feed URLs are the least invasive secure integration.

## Consequences

- Meilisearch outages must degrade to PostgreSQL search, and responses should include metadata indicating the backend used.
- Search documents can be eventually consistent. Admin workflows that require authoritative state must still fetch source data from owning contexts.
- Communication migration must avoid double-counting analytics while compatibility records remain.
- Attendance migration needs a projection path from Scheduling to Analytics and a compatibility path for existing analytics consumers.
- Calendar feed tokens become secrets. They should be signed, revocable in a later phase if needed, and omitted from logs where practical.

## Implementation Notes

- Added a Meilisearch-backed `AdminMemberSearchIndex` port and `MeilisearchMemberIndex` adapter. `AdminSearchUsers` rebuilds/upserts the denormalized member documents before query for MVP freshness and falls back to PostgreSQL when Meilisearch is unavailable. Responses expose `meta.search_backend`.
- Added Meilisearch compose/runtime configuration with local defaults and compose service wiring. The adapter configures searchable/filterable/displayed attributes and waits for indexing tasks before querying.
- Added durable communication recording through `Analytics.record_communication_message/1` and an application wrapper. Assignment messages, schedule slot messages, and admin coaching notes now mirror durable communication thread/message facts without removing their existing compatibility behavior.
- Added communication analytics summary slices by direction, channel, and thread status.
- Added Scheduling-owned `class_attendance_records` source facts. `Analytics.record_attendance/1` now validates booking ownership, writes the Scheduling fact, then writes the existing Analytics projection for compatibility. `Analytics.get_attendance_for_user_class/2` reads Scheduling first and falls back to the old Analytics table.
- Added signed calendar feed tokens, authenticated `/api/calendar/export-links`, and public `/api/calendar/feed.ics?token=...` feed delivery. Feed URLs include `webcal://`, HTTPS `.ics`, and download variants. The frontend exposes the same controls on Schedule and My Workouts/Workout Board pages with Google, Apple, Outlook, and download help text.
- Regenerated OpenAPI JSON and generated TypeScript schema after adding calendar endpoints.
- Focused backend tests passed for admin search, analytics communication/attendance, calendar feed, and finance controller search path. Frontend TypeScript and lint passed, with one pre-existing lint warning in `admin-finance.tsx`.
- Follow-up: Meilisearch indexing should move from query-time rebuild to event/job-driven incremental updates once source-fact events are stable at every Identity/Finance/Wellbeing/Feedback/Communication write boundary.
