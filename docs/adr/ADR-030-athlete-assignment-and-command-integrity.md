# ADR-030: Athlete Assignment and Command Integrity
Date: 2026-06-13
Status: Accepted

## Context
Shared assigned-workout headers currently carry mutable state that is actually
owned by each athlete, including rescheduled dates and communication. Execution
completion and annotations also accept client-authored facts without proving
that they match the server-owned workout structure. Refresh-token rotation,
notification fanout, and challenge progress updates use multi-step transitions
that lose correctness under concurrency or partial failure.

## Decision
Keep assigned-workout headers as bulk programming envelopes, but move
athlete-specific schedule state onto `assigned_workout_athletes` and scope every
assignment message to one athlete. Bind assigned execution completion to its
`source_reference_id`. Validate completion scores and execution annotations
against the server-materialized workout before persistence. Consume refresh
JTIs atomically in the token-store adapter, preserve recipient delivery errors
through Oban jobs, and advance challenge progress with one atomic store
operation per completion.

## Rationale
These changes preserve the existing bulk-assignment workflow while giving each
athlete an isolated state boundary. Server-owned workout structure is the only
trustworthy source for score and annotation facts. Atomic adapter operations
are required where correctness depends on a state transition being observed
and changed as one operation.

## Alternatives Considered
Creating one assignment header per athlete was rejected because it would
duplicate the admin-authored programming envelope and require a larger API
migration. Keeping shared messages with UI filtering was rejected because it
would leave the authorization flaw in persistence. Application-level locks
were rejected for token and gamification transitions because they do not
coordinate across nodes.

## Consequences
Assignment links gain an optional athlete-specific scheduled date and messages
gain a required athlete recipient. Existing rows are backfilled from their
assignment header and sender/recipient relationships. Assigned execution reads
must use assignment identity rather than workout identity. Token-store and
gamification-store ports gain atomic operations. Invalid client score or note
payloads are rejected before any durable side effects occur.

## Implementation Notes
Implemented on 2026-06-13.

- Added `scheduled_for` to `assigned_workout_athletes` and made athlete
  rescheduling update that link row instead of the shared assignment header.
  Athlete week views now filter by the link date.
- Added `athlete_id` to assignment messages and scoped list/post operations to
  one athlete thread. Admins must provide `athlete_id` when a shared assignment
  has multiple recipients; single-recipient assignments infer it.
- Assigned workout completion projection now keys off
  `workout_executions.source_reference_id` for `source = assigned`, so reusing a
  workout template across dates no longer marks every assignment complete.
- Completion no longer accepts client-authored `exercise_notes`, and manual
  section scores are validated against the server-built timer sequence before
  persistence.
- Execution annotations now validate that the exercise belongs to the
  execution's materialized workout and that the selected offsets match the
  exercise label text.
- Refresh-token rotation now uses a token-store `consume/2` operation backed by
  Redis `SET ... NX PX`, with the in-memory test store using atomic ETS
  insertion.
- Booking notification fanout now returns the first recipient failure so
  `NotificationEventJob` remains retryable.
- Challenge progress updates now lock the challenge row inside the existing
  gamification transaction before reading or inserting per-user progress.
