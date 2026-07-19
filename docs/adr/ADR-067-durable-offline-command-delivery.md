# ADR-067: Durable offline command delivery
Date: 2026-07-19
Status: Accepted

## Context
Phoenix Channels acknowledge chat commands while a connection is available, but
the web client currently keeps an unsent message only in component memory. A
browser close, route change, or sign-out therefore loses the user's intent
before the server can persist it. Retrying after an uncertain timeout can also
create duplicate messages because Messaging has no client operation identity.

The existing IndexedDB execution queue solves a narrower optimistic-concurrency
problem. Messaging and the journal redesign need a durable, user-scoped command
outbox whose records survive browser restarts and sign-out, while preserving the
server as the canonical multi-device source of truth.

## Decision
Adopt an opt-in durable offline command protocol:

1. The web client writes an operation with a stable UUID to IndexedDB before it
   attempts network delivery. Operations are scoped to the initiating user and
   remain stored across route changes, browser restarts, and sign-out.
2. A signed-in client reconciles only operations owned by that same user on
   application startup, login, browser `online`, and explicit retry. Pending
   content is never exposed or sent while another account is active.
3. IndexedDB remains device-local. An operation becomes available to other
   devices only after the originating device reconnects and the server accepts
   it. The client requests persistent browser storage on a best-effort basis and
   labels unacknowledged records as pending rather than delivered.
4. Every queued command type must opt in with server-side idempotency,
   authorization revalidation, and explicit conflict semantics. This ADR first
   enables `send_message`; it does not automatically queue arbitrary HTTP
   mutations.
5. Messaging accepts `client_operation_id` over both REST and Channel command
   paths. A sender-scoped database uniqueness constraint makes retries return
   the existing message without creating another delivery job, notification,
   analytics event, or realtime broadcast.
6. Message persistence and the Oban delivery handoff remain atomic. Realtime
   and Web Push continue to be non-authoritative accelerators after the server
   commit.
7. Permanent authorization or validation failures remain visible as failed and
   are excluded from automatic replay. Network failures remain pending and
   retry automatically.

## Rationale
A local outbox is the only place an offline browser can durably record intent.
Stable operation identities close the acknowledgement ambiguity between client
and server, while sender scoping prevents cross-account disclosure on shared
devices. An opt-in protocol avoids replaying commands such as booking approval
without checking versions and current authorization. Keeping notification
dispatch behind the unique server commit prevents duplicate user-visible side
effects.

## Alternatives Considered
- Keeping drafts in React state was rejected because component and browser
  lifetimes are shorter than the user's delivery expectation.
- Clearing the outbox on sign-out was rejected because signing back into the
  same account must resume delivery. Pending data is hidden instead.
- Queuing every failed mutating request was rejected because commands have
  different conflict, authorization, file-upload, and expiry semantics.
- Service Worker Background Sync as the only replay path was rejected because
  browser support and background execution are not reliable, and access tokens
  intentionally live only in application memory.
- Treating IndexedDB as multi-device storage was rejected because no device can
  synchronize an operation that has never reached a shared server.

## Consequences
- An additive Messaging migration and OpenAPI contract change are required.
- The web application gains a reusable, versioned device outbox and a global
  authenticated reconciliation bridge.
- Sign-out cleanup must not erase the durable outbox.
- Future journal, booking, and coaching commands may reuse the envelope only
  after their owning contexts implement idempotency and conflict policies.
- Browser data deletion, private-session closure, or loss of the originating
  device before synchronization remain unavoidable loss boundaries.

## Implementation Notes
Implemented 2026-07-19.

- Messaging gained an additive nullable `client_operation_id` and a
  sender-scoped unique index. REST and Channel payloads expose the same UUID.
  The Ecto adapter uses `ON CONFLICT DO NOTHING` through changeset insertion,
  returns the canonical existing message on replay, and inserts the Oban
  delivery job only for the first database row.
- Coaching-note delivery derives its entitlement delivery identity from the
  client operation UUID when present, so a retry also converges at the Finance
  idempotency boundary.
- The web client now writes messages to a versioned per-device IndexedDB outbox
  before attempting REST delivery. Records include owner, thread, operation
  UUID, creation order, attempts, and pending/failed status. Sign-out cleanup
  does not erase this database, and reconciliation selects only the active
  user's records.
- A root-level authenticated bridge reconciles on app/login bootstrap, browser
  `online`, and return to a visible tab. Open chats combine canonical server
  history with local operations and replace pending bubbles by operation UUID
  after acknowledgement.
- Verification completed with `454` backend tests, `76` frontend tests,
  TypeScript, ESLint, Credo, formatting, the hexagonal architecture gate,
  localization checks across 12 locales, generated OpenAPI output, and a
  production Next.js build. A Playwright live test on desktop and mobile queued
  a message offline, closed the page, reopened the same browser profile online,
  observed exactly one server POST, and replaced the pending bubble with the
  canonical message.
