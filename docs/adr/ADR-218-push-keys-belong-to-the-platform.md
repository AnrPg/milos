# ADR-218: Web Push keys belong to the platform console, not to a gym's settings
Date: 2026-10-28
Status: Accepted (supersedes the placement in ADR-049; key editor superseded by ADR-275)

## Context
ADR-049 moved the Web Push (VAPID) key pair out of environment variables into a
persisted `notification_push_settings` row and put the editor in the admin
settings hub, when the app served one gym. Palee is now multi-tenant: that row
has no `organization_id` and signs pushes for every business. Any gym owner
could therefore generate or paste keys that replaced the keys of every other
gym, and every browser subscription made with the old public key would stop
receiving alerts. A box owner also met technical fields («Δημόσιο κλειδί»,
«Ιδιωτικό κλειδί») with no explanation (ANR, 2026-10-28).

## Decision
- The keys are platform configuration. `GET/PATCH /api/platform/push-settings`
  (vendor pipeline) reads and edits them; the private key is never returned.
- `/api/org/:slug/admin/settings` no longer returns or accepts `notifications`;
  a gym admin's request that still sends it changes nothing.
- The web editor moves to `/platform/push` («Ειδοποιήσεις συσκευών»), linked
  from the platform dashboard. Every field has a help line under it: what the
  contact is for (`mailto:` added to a plain email), that the public key is
  shared with devices, that the private key is secret and kept when left empty,
  and a warning that new keys make every device allow alerts again.
- The box settings hub has no Notifications section. Members keep the per-device
  opt-in in the bell panel; gym-level reminder timing stays in Finance.

## Rationale
One key pair per installation is how Web Push works: browsers subscribe with
the application server key, so per-gym keys would need per-gym subscriptions
and the service worker would have to pick a key per gym. Keeping the existing
row and moving only who may edit it fixes the cross-tenant write with no data
migration and keeps ADR-049's goal (no server access needed to set it up).

## Alternatives Considered
- Per-gym key pairs: rejected; a person in several gyms would need several
  subscriptions per device for no gain, and the platform still sends the push.
- Environment variables only: rejected again for ADR-049's reasons; they stay
  as a fallback (`WEB_PUSH_*`), as the help text says.

## Consequences
Only vendors can turn browser alerts on for the platform. Replacing keys still
invalidates existing subscriptions; the page warns before saving.

## Implementation Notes
`PlatformPushSettingsController`, `PlatformPushSettingsPage`, `lib/web-push-keys.ts`
(key generation and contact normalisation, unit-tested), e2e
`box-settings-help.spec.ts`.
