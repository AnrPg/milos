# Notification Read and Push Subscription Hardening
Date: 2026-06-11
Status: Implementation context anchor

## Purpose

This note records notification-related fixes and decisions from the same
planning session so future agents do not regress them while implementing Phase 8
communication and analytics features.

## Notification Read State

Problem observed:
- Clicking a notification navigated correctly, but the notification remained unread.
- Backend returned 500 on `POST /api/notifications/:id/read`.
- Ecto rejected `DateTime.utc_now()` with microseconds for a `:utc_datetime` field.

Fix implemented:
- `MilosTraining.Infrastructure.Notifications.EctoNotificationStore` now writes second-precision timestamps for both single-read and mark-all-read paths.
- Controller regressions cover:
  - `POST /api/notifications/:id/read`
  - `POST /api/notifications/read-all`

Important future analytics implication:
- `read_at` supports notification read status.
- Click-through status is still missing as a separate fact. Add `notification_click_events` or `clicked_at` if analytics need click-through rate.

## Browser Push Enable Prompt

Problem observed:
- The browser push enable section stayed visible after the user clicked Enable.
- The UI originally inferred success from browser permission or from local subscription state.

Hardening implemented:
- `usePushNotifications` now models setup as explicit states:
  - `checking`
  - `ready`
  - `blocked`
  - `enabling`
  - `enabled`
  - `error`
- It also tracks exact setup steps:
  - `fetch-config`
  - `register-worker`
  - `browser-subscription`
  - `server-save`
  - `server-verify`
  - `complete`

The enable section should disappear only after the full path succeeds:
1. Server push config fetched.
2. Service worker registered.
3. Browser push subscription exists.
4. Subscription saved to server.
5. Server status endpoint confirms the exact endpoint is persisted for the authenticated user.

## Server Truth Endpoint

Endpoint added:

`POST /api/notifications/push-subscriptions/status`

Request body:

```json
{
  "endpoint": "browser push endpoint"
}
```

Response:

```json
{
  "registered": true,
  "subscription": {}
}
```

or

```json
{
  "registered": false,
  "subscription": null
}
```

Future analytics implication:
- This confirms persistence, but it is not a push delivery receipt.
- Push dispatch status still needs a persisted attempt/result table if analytics need delivery success/failure.

## Known Follow-Up for Communication Analytics

Needed for Phase 8 communication analytics:
- Persist notification click-through facts.
- Persist push dispatch attempts and final outcomes.
- Add communication threads/messages if response latency and unanswered-message age are required.
- Emit telemetry for notification read, notification click, and push dispatch result.

