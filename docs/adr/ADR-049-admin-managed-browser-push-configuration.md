# ADR-049: Admin-managed browser push configuration
Date: 2026-07-16
Status: Accepted

## Context
Browser push was treated as a deployment-only capability controlled by API
environment variables. That leaked infrastructure instructions into the
notification panel and left non-technical gym owners without an in-app way to
make browser alerts available.

## Decision
Notifications owns a persisted Web Push settings record. Admin settings exposes
that record as an app-configuration surface where admins can save or generate
VAPID credentials and a contact subject. Members and athletes continue to see
only the per-browser/device opt-in controls in the notification panel.

## Rationale
The VAPID key pair is a gym-wide notification-delivery setting, not a personal
preference. Keeping it in Notifications preserves bounded-context ownership,
while surfacing it through the existing admin settings hub matches the product
model of an owner-operated app.

## Alternatives Considered
Keeping environment-only setup was rejected because it requires codebase/server
access and creates hostile end-user guidance.

Letting every user edit push service credentials was rejected because the keys
control delivery for the whole installation.

Storing the private key only in browser local storage was rejected because the
API must sign background push deliveries after the admin closes the browser.

## Consequences
The database now stores a Web Push private key, so database access must be
treated as operationally sensitive. Environment-provided keys remain useful as
a bootstrap fallback, but persisted admin settings take precedence.

## Implementation Notes
Implemented with a Notifications-owned `notification_push_settings` table and
store methods that expose public admin status while keeping the private key out
of response payloads. The push dispatcher applies the persisted delivery config
to `web_push_elixir` before sending, with existing environment variables kept as
fallback bootstrap configuration.

The admin settings contract now includes `notifications`, and PATCH requests may
update only the changed settings group. The web app adds a Browser Alerts section
to App Configurations where admins can generate a P-256 VAPID key pair in the
browser, save the contact subject, replace keys, or turn browser alerts off.
Members and athletes keep only the notification-panel per-device opt-in/out.

The previous end-user-facing VAPID/environment-variable instructions were
removed from active web catalogs. Catalog parity passes; the remaining
`i18n:check` hard-coded-copy failures are pre-existing finance `InlineCell`
findings unrelated to this change.
