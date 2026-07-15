# ADR-010: Notification Delivery and Web Push
Date: 2026-06-09
Status: Accepted

## Context

Phase 6 introduces the first complete notification delivery slice. The system
already emits internal PubSub events for scheduling, execution, and future
cross-context side effects, but the current implementation only persists
partial in-app notifications and uses event-specific push stubs. The design doc
requires:

- in-app notifications via the notification bell
- Web Push delivery via Service Worker
- Oban-backed asynchronous delivery
- strict Notifications bounded-context ownership for notification records and
  push subscriptions
- future compatibility with later-phase events such as admin notes and
  challenge completion

The key decision is where delivery orchestration lives and how to prevent push
transport concerns from leaking into scheduling, execution, or controller code.

## Decision

The Notifications context owns both notification persistence and push
subscription persistence, and it delivers Web Push through a generic
Oban-backed `PushDispatchJob`.

The concrete design is:

- event producers broadcast semantic PubSub events only
- `MilosTraining.Notifications.EventHandler` translates those events into
  notification writes plus enqueueing of push work
- notification records persist normalized semantic payloads, including a
  destination URL for click-through
- push subscriptions are stored in a dedicated `push_subscriptions` table,
  scoped to the owning user and unique by endpoint
- `PushDispatchJob` loads the user subscriptions and calls a push-dispatcher
  port implemented by infrastructure
- push transport failures never roll back the primary action; they are isolated
  to Oban retries and invalid subscriptions are pruned
- backend configuration exposes a read-only push capability endpoint so the
  frontend can register the Service Worker and subscribe with the server’s
  public VAPID key

## Rationale

Using Oban as the delivery boundary keeps HTTP responses and primary workflow
transactions fast while making retries explicit and observable. Keeping push
subscriptions inside the Notifications context preserves the bounded-context
boundary and avoids pushing browser-delivery concerns into Identity or
Scheduling.

Normalizing a generic push pipeline now also avoids per-event worker
proliferation. Booking approvals, workout notes, admin notes, and future
challenge completion can all reuse the same job and dispatcher path while only
changing semantic payload construction in the Notifications context.

## Alternatives Considered

Direct push delivery inside event handlers:
rejected because a slow or failing push provider would couple user-facing
latency to a non-critical side effect and would reduce retry control.

Event-specific push workers per notification type:
rejected because it duplicates delivery plumbing and makes future phase events
harder to add consistently.

Storing browser subscriptions inside Identity:
rejected because subscriptions are operational delivery endpoints, not identity
credentials, and their lifecycle is tied to notification transport.

## Consequences

The Notifications context becomes the single place where notification payload
shape, click-through routing, and delivery fanout are defined.

The system now depends on VAPID configuration for browser push. In-app
notifications still function when push is not configured, but Web Push delivery
degrades gracefully to a no-op with logging.

Future phases must publish semantic events or call the Notifications public API
rather than writing notification rows directly.

## Implementation Notes

- Added `push_subscriptions` persistence with endpoint-unique upserts and
  user-scoped deletion, allowing a browser/device subscription to be
  re-associated cleanly with the current authenticated user.
- Corrected the production Web Push integration to match the installed
  `web_push_elixir` contract by configuring VAPID credentials under the
  library's application env and dispatching through its `send_notification/2`
  API.
- Push delivery now enqueues one Oban job per live subscription endpoint
  instead of one fanout job per user. This preserves retry semantics for
  transient endpoint failures without forcing successful devices to be retried
  alongside failed ones.
- Notification enqueue failures now surface back through the Notifications
  slice while still broadcasting the persisted in-app notification, so the bell
  stays truthful even when background push enqueueing is degraded.
- Added a generic `PushDispatchJob` plus `PushMessageBuilder` so booking,
  execution, admin-note, and challenge-completion payloads share one delivery
  path rather than per-event worker logic.
- Notification payload normalization now stringifies nested maps and converts
  `DateTime` / `NaiveDateTime` values to ISO8601 strings before persistence,
  fixing a real event-handler crash discovered during the audit.
- Exposed authenticated notification endpoints for push config, subscription
  create/update, and subscription delete, then regenerated the OpenAPI schema.
- Brought the admin-to-athlete note producer online through a minimal Coaching
  bounded-context slice and admin endpoint, so `coaching:note_written` is now a
  real integrated producer rather than a future-only subscription hook.
- Added a test-sandbox allowance for `MilosTraining.Notifications.EventHandler`
  so controller/application tests can exercise the async PubSub notification
  path without DB ownership races.
- The browser UI enables push explicitly from the notification panel instead of
  prompting automatically on sign-in. This is a deliberate UX hardening choice
  to avoid surprise permission prompts while still satisfying the Phase 6
  service-worker and push-subscription requirements.
- Refactored the notification bell to use TanStack Query for inbox server
  state, keeping stale data during transient failures and marking realtime
  degradation explicitly instead of presenting a false zero-unread state.
- Replaced the race-prone booking notification read-then-write guard with an
  atomic dedupe model: booking events now carry a deterministic `dedupe_key`
  and the Notifications table enforces uniqueness with a partial index scoped
  by user.
- Introduced a dedicated inbox read model with cursor pagination plus a store-
  level unread counter so the bell no longer reloads the full notification
  history to render its top-level state.
- Added service-worker subscription-rotation recovery by caching the VAPID
  public key, handling `pushsubscriptionchange`, and re-synchronizing the new
  browser subscription through the authenticated API.
- Sign-out and session-expiry flows now clear the local browser push
  subscription and best-effort delete the server-side subscription record so a
  shared browser cannot keep receiving the previous user’s notifications.
- Notification-record creation no longer depends on a dedicated runtime PubSub
  subscriber. Producers now schedule a Notifications-owned `NotificationEventJob`
  through the Notifications public API, which provides durable Oban-backed
  retries for the user-visible notification write path and falls back to direct
  processing if Oban is unavailable.
- The Service Worker is now registered globally from the root app layout
  instead of only from push-capable or workout-specific entry paths, making the
  Phase 6 browser runtime available consistently across the app.
- Push-subscription controller actions are now validated against their declared
  contract, and the exported OpenAPI spec again marks push-subscription create
  as a required request body while documenting delete as a validated query-
  parameter operation.
- The web notification API helpers now derive their request/response types from
  the generated OpenAPI schema instead of duplicating notification DTO shapes
  by hand.
- Moved the athlete note composer out of the generic admin landing page and
  into a dedicated `/admin/coaching` route so the producer exists for Phase 6
  without collapsing the planned Phase 8 coaching surface into the wrong UI.
- Stabilized challenge-completion delivery around a single producer path:
  gamification now returns completed challenge payloads from workout
  processing, and the application orchestration layer emits the semantic PubSub
  events consumed by Notifications.
- Split the Service Worker concerns into imported execution-cache and
  push-notification modules so Phase 6 no longer mixes those behaviors in one
  monolithic script.
- Moved push-subscription deletion away from query-string endpoint transport to
  a validated request body, preventing raw browser push endpoints from leaking
  through routine URL logging paths.
- Tightened push-subscription save semantics so the API now distinguishes
  created subscriptions from endpoint updates, returning `201` only for true
  creates and `200` for upserts against existing endpoints.
- Added single-notification read support and wired notification click-through
  to mark inbox items read before navigation, keeping unread counts aligned
  with actual user consumption rather than only bulk-read actions.
- Notification payloads are now enriched with canonical `title`, `body`, and
  `url` values at creation time from one builder path so in-app inbox rendering
  and Web Push copy stay consistent for the same semantic event.
- Athlete-facing landing data now includes recent coach notes, and admin-note /
  challenge notifications target anchored landing sections so click-through
  lands on relevant content instead of a generic root route.
- ADR-031 hardened the imported execution-cache module so authenticated workout
  and execution responses are stored in per-user cache namespaces. Session
  establishment, sign-out, expiry, and role-change invalidation now update the
  Service Worker identity and clear prior authenticated workout caches.
