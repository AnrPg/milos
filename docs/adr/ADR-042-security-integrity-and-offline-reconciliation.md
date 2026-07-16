# ADR-042: Security, integrity, and offline reconciliation
Date: 2026-07-15
Status: Accepted

## Context
The messaging, workout-execution, authentication, object-storage, and delivery
paths were implemented incrementally and expose several cross-cutting integrity
gaps. Contextual chat membership is not authorized by the context that owns the
referenced object; chat and execution mutations lack reliable acknowledgement
and concurrency protocols; refresh credentials are available to browser
JavaScript; avatar uploads do not enforce an object policy; authenticated cache
entries can outlive authorization; and container publication is not coupled to
verification.

These concerns cannot be fixed reliably in controllers or UI components alone.
They require protocols that are enforced at the owning bounded-context and
infrastructure boundaries and that remain valid for HTTP, Phoenix Channels,
offline clients, and future native clients.

## Decision
Adopt the following coordinated hardening protocols:

1. A cross-context Application service authorizes contextual messaging access
   through the public `Workouts` and `Scheduling` APIs before invoking
   Messaging. Assignment access is limited to the assigned athlete and admins;
   class-slot access is limited to admins and users with an approved booking.
   Messaging never treats possession of a context UUID as authorization.
2. Thread creation is atomic. Direct conversations use a canonical participant
   pair identity protected by a database uniqueness constraint, prohibit
   self-conversations, and converge under concurrent creation. Contextual thread
   membership changes occur in the same transaction as creation or lookup.
3. Read pointers are advanced transactionally only to messages in the same
   thread. They are monotonic by message ordering and cannot be moved backward
   or across threads.
4. Chat Channels use an acknowledged command protocol. Typing state has explicit
   `typing_start` and `typing_stop` events and a stable payload. Message sends
   return success or structured failure replies; the client preserves drafts
   until acknowledgement.
5. Workout execution progress is an optimistic-concurrency aggregate. Every
   snapshot carries a `lock_version`; updates require the caller's expected
   version and fail with HTTP 409 when stale. A pure domain validator checks
   segment position, check-off identifiers, repeat counters, elapsed values,
   map keys, and payload bounds against the materialized timer sequence.
6. Offline execution mutations are durable, ordered operations stored in
   IndexedDB. Only check-offs are applied optimistically. Queued operations have
   stable UUIDs and base versions, are idempotent on the server, and reconcile
   on reconnect by fetching current state and replaying valid operations.
   Authenticated cached reads are versioned, bounded by TTL, and evicted rather
   than served when the origin reports 401 or 403.
7. Browser refresh credentials use rotating `HttpOnly`, `Secure` in production,
   `SameSite=Strict` cookies scoped to authentication endpoints. Access tokens
   exist only in memory. Refresh families carry the user's persisted security
   version; password changes and the sign-out-all-devices command atomically
   increment it, invalidating existing access and refresh credentials.
8. Production responses enforce a nonce-based Content Security Policy. Script
   execution is limited to the application origin; development-only allowances
   are not enabled in production.
9. Avatar uploads use policy-constrained presigning with an allowlist of image
   MIME types, a strict byte limit, user-scoped generated object keys, and
   server-derived public URLs. Profile commands reject arbitrary avatar URLs.
10. The production API receives explicit internal and public MinIO endpoints and
    credentials from Compose and waits for object-storage health. Public media
    delivery is routed through the configured external MinIO origin.
11. Container publication uses immutable commit tags and is gated in the same
    workflow on backend and frontend verification jobs. Images are not pushed
    when tests, static analysis, contract generation checks, or builds fail.

## Rationale
Authorization is strongest when the owning context answers the access question,
and integrity is strongest when invariants are protected by both application
logic and database constraints. Versioned commands make conflicts visible
instead of silently discarding progress. Durable idempotent operations support
offline work without expanding optimistic UI beyond check-offs. Cookie-bound
refresh credentials materially reduce XSS exposure while short-lived in-memory
access credentials keep API requests practical. Constrained upload policies and
test-gated immutable images move enforcement to boundaries attackers or faulty
clients cannot bypass.

## Alternatives Considered
- Controller-only ownership checks were rejected because Channels and future
  entry points could bypass them and controllers would import other contexts.
- A global Messaging query over assignment and booking schemas was rejected as
  a bounded-context violation.
- Last-write-wins progress updates and automatic overwrite retries were rejected
  because they can silently lose valid check-offs.
- Persisting encrypted refresh tokens in local storage was rejected because the
  browser must still expose the decryption path to injected JavaScript.
- Cache-only offline support was rejected because it cannot preserve mutations.
- Unrestricted presigned PUT URLs were rejected because they cannot enforce the
  required size and media policy at the object-store boundary.
- Publishing from an independent build workflow was rejected because workflow
  timing does not prove that the published commit passed verification.

## Consequences
- Additive migrations are required for canonical direct-thread identity,
  execution versions and idempotency operations, refresh security versions, and
  constrained media metadata.
- Web authentication becomes session-bootstrap based; page reloads silently use
  the refresh cookie to mint a new in-memory access token.
- Execution clients must surface and resolve 409 conflicts and retain queued
  operations across reloads.
- Local HTTP development permits non-secure cookies; production refuses that
  relaxation.
- Existing externally hosted avatar URLs require a compatibility migration or
  removal before arbitrary URL assignment can be fully disabled.

## Implementation Notes
Implemented 2026-07-16.

- Contextual messaging now flows through `MilosTraining.Application.GetOrCreateMessagingThread`.
  It asks the Workouts and Scheduling public APIs whether the caller may access
  assignment/class-slot context before creating or joining a thread. Controller
  and channel tests cover foreign assignment and class-slot IDs.
- Messaging persistence gained additive constraints for direct-thread identity,
  message sequencing, read-pointer integrity, and user foreign keys. Direct
  thread creation is transactional, self-chat is rejected, and legacy duplicate
  direct threads converge through deterministic lookup without destructive data
  merging.
- Chat push handling now acknowledges `send_message`, `typing_start`, and
  `typing_stop`; the web realtime wrapper returns Phoenix push replies as
  promises so the UI preserves drafts on authorization, validation, disconnect,
  and timeout failures.
- `mark_read` now requires a same-thread `message_id`, advances monotonically
  by message sequence, and has an aligned OpenAPI/controller/frontend contract.
- Message delivery side effects moved behind a durable Oban handoff. The outbox
  job dispatches realtime broadcast, notifications, analytics, and cache
  invalidation outside the request transaction while preserving retryability.
- Execution progress gained `lock_version`, idempotent progress operation UUIDs,
  pure semantic payload validation, 409 stale-version responses, and frontend
  conflict-aware offline replay. Only check-offs are optimistic; navigation,
  pause/resume, repeat-cycle, and finish-review mutations now persist before UI
  commitment or roll back all affected local state.
- Refresh sessions moved to rotating HttpOnly refresh cookies with in-memory
  access tokens. User `security_version` invalidates existing token families on
  password change and sign-out-all-devices.
- Avatar upload requests now use constrained object-store policies, allowlisted
  image MIME types, byte limits, generated user-scoped keys, and server-derived
  public URLs. Arbitrary avatar URL assignment is rejected.
- MinIO runtime config now requires explicit production internal/public
  endpoints and credentials; Compose passes them to the API. A storage bucket
  reconciler creates/validates invoice and avatar buckets so readiness reflects
  usable object storage.
- The service worker now applies authenticated cache TTLs, clears protected
  cached responses on 401/403, and participates in offline execution mutation
  reconciliation.
- Verification included full backend tests before the final dependency work,
  focused controller/channel/storage tests, live `/api/health` object-storage
  readiness, frontend type/lint/build checks, and the final frontend unit/E2E
  gates recorded in ADR-044.
