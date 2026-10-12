# ADR-120: Offline Outbox Failure Controls and Command Adapters
Date: 2026-10-12
Status: Accepted

## Context
ADR-067 introduced a durable, per-user IndexedDB outbox for chat messages:
transient failures stay pending and replay automatically with a stable
operation UUID, while permanent failures are marked `failed` and excluded from
replay. Two gaps remained (TD-035):

1. A permanently failed message had no user-facing controls. The bubble said
   "Message could not be sent" forever; the user could neither retry it nor
   remove it, and the reason (authorization, validation, conflict) was lost
   because the record only kept a free-text error.
2. Other notification-triggering commands (booking requests, admin booking
   approval/rejection, training-log entries) were lost when the network
   dropped. ADR-067 deliberately forbade replaying them generically: each one
   has its own authorization, conflict, and side-effect semantics (finance
   reservations, staff/member notifications, Oban jobs, gamification
   projections), so a retry after an ambiguous timeout could double-book,
   double-notify, or approve a booking another admin already rejected.

## Decision
1. **Failure classification is explicit and shared.** A delivery error becomes
   an `OutboxFailure { category, status?, code? }` with three categories:
   `transient` (network failure, 401 session expiry, 408/425/429, 5xx; stays
   pending and replays automatically), `permanent` (other 4xx; never replayed
   automatically) and `conflict` (409, or adapter-declared codes; never
   replayed automatically, surfaced for review). The structured failure is
   persisted on the outbox record and mapped to localized copy through the
   existing API error catalog.
2. **Failed operations get explicit UX.** Failed messages show the reason with
   *Retry* (re-enqueue with the same operation id, then deliver) and *Discard*
   (two-step inline confirmation) directly in the chat bubble. A global outbox
   status pill (bottom-start, only visible while something is waiting or
   failed) opens a panel listing every waiting/failed message and command of
   the signed-in user with the same controls.
3. **Non-message commands opt in through explicit adapters.** A separate
   `command-operations` store (same device database, schema version 2,
   additive upgrade) holds commands whose `kind` has a registered adapter. The
   registry is a closed list in `offline-command-adapters.ts`:
   `booking.request`, `booking.approve`, `booking.reject`,
   `training_log.create`. Each adapter declares its idempotency key
   derivation, how it sends (pinned to the organization the user acted in),
   its retry classification, and its conflict codes. Unregistered kinds are
   never sent; a stored record of an unknown kind is parked as a permanent
   `unsupported_operation` failure.
4. **Foreground vs background semantics.** A command is written to the outbox
   before the first attempt. If the first (foreground) attempt fails
   permanently or with a conflict, the record is removed and the error is shown
   inline, because the user is present. Only transient failures are kept for
   background replay, which runs on bootstrap, `online`, tab focus, and
   explicit retry, in creation order, stopping at the first transient failure.
5. **Owning contexts implement idempotency and conflict policy server-side.**
   - *Scheduling / booking request*: `POST /bookings` accepts an optional
     `client_operation_id` (UUID, body field, same name as Messaging). The
     booking stores it under a partial unique index on
     `(organization_id, user_id, client_operation_id)`. A replay for the same
     slot returns the original booking with `200` and reserves no class visit,
     sends no notification, and broadcasts nothing; reusing the id for another
     slot is `409 idempotency_key_conflict`. The lookup runs before the finance
     reservation and again after a lost insert race.
   - *Scheduling / booking resolution*: approve/reject accept an optional
     `client_operation_id`, stored as `resolution_operation_id` when the
     booking is resolved. Inside the existing `FOR UPDATE` transaction,
     `BookingOperationPolicy` decides: pending → resolve; already resolved by
     the same operation with the same outcome → replay (`200`, no notification,
     release job, or broadcast); same operation, other outcome →
     `409 idempotency_key_conflict`; resolved by anything else →
     `409 booking_not_pending` (never replayed).
   - *Execution / training log*: ADR-118's `idempotency_key` is reused (the
     outbox operation id equals the form's key). A replay is now resolved
     *before* source authorization, so an acknowledged-but-unconfirmed write
     converges on its entry even if the class or assignment stopped
     authorizing. Reusing a key for a different source is
     `409 idempotency_key_conflict`.

## Rationale
Explicit adapters keep the ADR-067 promise that no command is replayed unless
its owning context has an idempotency and conflict policy. Classifying 409s as
conflicts (not permanent errors and not retryable) matches the server's
semantics: the data moved on, and the user must look before trying again.
Reusing existing columns and tables (bookings, training-log entries) avoids a
generic idempotency-key table that would need its own retention, RLS, and
payload-fingerprint semantics. Pinning the organization slug at enqueue time
prevents a replay from landing in a different tenant after an organization
switch. Removing foreground permanent failures avoids a second, stale copy of
an error the user has already seen.

## Alternatives Considered
- **A generic `Idempotency-Key` header plus a shared idempotency table** that
  caches responses for any mutation: rejected; it would make every command
  replayable by default (the opposite of ADR-067), needs response caching and
  request fingerprinting, and still cannot express per-command conflicts such
  as "another admin already rejected this booking".
- **Natural idempotency only** (treat approve-of-approved as success):
  rejected; it hides the case where a different admin resolved the booking
  with a different message, which must surface as a conflict.
- **Automatic retry of permanent failures with back-off**: rejected; 4xx
  responses will not change without user action, and silent repeated attempts
  waste battery and obscure the reason.
- **Keeping failed foreground commands in the outbox**: rejected; the user
  already sees the inline error, so a lingering failed record duplicates it.
- **Discard via `window.confirm`**: rejected in favor of inline confirmation,
  which is localizable, accessible, and works inside the chat bubble on
  mobile.

## Consequences
- Bookings gain two nullable UUID columns and one partial unique index
  (additive migration on an already tenant-scoped, RLS-forced table already
  declared in the Scheduling `TenantDataPolicy`).
- `ResolveBooking.call/3` now returns `{:ok, booking, :resolved | :replayed}`;
  `SubmitBooking.call/4` returns `{:ok, booking, :created | :replayed}` while
  `call/3` keeps the historical shape.
- `POST /bookings` can now answer `200` for a replay; clients must accept both
  `201` and `200`.
- New offline-capable commands must add an adapter *and* a server-side
  idempotency/conflict policy in their owning context; the registry test pins
  the allowed list.
- A booking withdrawal deletes the booking row, so a replay arriving after a
  withdrawal creates a new booking. The client removes acknowledged
  operations, so this needs a lost acknowledgement *and* a withdrawal in
  between; accepted and documented.

## Implementation Notes
Implemented 2026-10-12 (TD-035).

- **Backend.** Migration `20261012110000_add_booking_operation_ids`. Pure
  `Scheduling.Domain.BookingOperationPolicy` (submission replay, resolution
  decision, UUID normalization without Ecto). The scheduling port gained
  `create_booking/5`, `create_approved_booking/4`,
  `get_booking_by_client_operation/3`, and `resolve_booking_operation/4`;
  older arities delegate with no operation id. The resolution path inserts the
  reject reconciliation job only for `:resolved`, and cancels the timeout job
  only then. `TrainingLogPolicy.replay_decision/2` and
  `Execution.find_training_log_replay/2` implement the training-log replay
  rule; the command applies the same check after authorization as a
  backstop. `FallbackController` maps `:idempotency_key_conflict` to 409.
- **Contract.** OpenAPI documents `client_operation_id` on the booking request
  and both resolution bodies, the `200` replay response, and the 409/422
  responses; the training-log `create` description states the replay and
  conflict policy. The TypeScript client was regenerated.
- **Frontend.** `src/lib/device-outbox-db.ts` (shared database, version 2),
  `src/lib/outbox-failure.ts` (classification and localized reasons),
  `src/lib/offline-command-outbox.ts` (store interface with IndexedDB and
  in-memory implementations, submit, reconcile, retry, discard),
  `src/lib/offline-command-adapters.ts` (closed registry),
  `src/hooks/useOutboxCommand.ts`, `OutboxFailureControls`, and the global
  `OutboxStatusPanel` mounted in the root layout. `ScheduleConsole` routes
  booking requests and approvals/rejections through the outbox and shows a
  queued notice; the training-log create form does the same (edits stay
  online-only because they carry an optimistic-lock version). The sync bridge
  reconciles commands after messages and invalidates the affected queries.
  Existing ADR-067 message records keep working: `lastError` is read as an
  unknown failure until the next attempt writes a structured `failure`.
- **Message classification change.** ADR-067 treated every 4xx as permanent;
  401/408/425/429 are now transient so an expired session or throttling no
  longer strands a message as failed.
- **i18n.** 34 new `Ui` keys in all 12 locales (outbox panel, controls, kinds,
  failure reasons, and booking/idempotency API error codes).
- **Verification.** Domain unit tests (`BookingOperationPolicy`,
  `TrainingLogPolicy.replay_decision/2`), DB integration tests for booking
  request and resolution replay (including two-tenant scoping and no duplicate
  timeout jobs, notifications, or release jobs) and training-log replay before
  authorization, ConnCase tests for the HTTP contract, and vitest coverage for
  the registry, adapters, submit/reconcile/retry logic, failure mapping,
  snapshot grouping, and the Retry/Discard controls. No browser live test was
  run in this session.
- **Deferred.** No new storage for idempotency keys was needed. Coaching
  commands, journal edits, attendance marks, and slot editing remain
  online-only. Message replay still uses the Channel-independent REST path
  only. The outbox panel lists operations for the current user across
  organizations without grouping by organization.
