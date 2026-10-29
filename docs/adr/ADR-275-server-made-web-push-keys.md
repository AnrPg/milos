# ADR-275: The server makes and keeps the Web Push keys; the console shows status only
Date: 2026-10-29
Status: Accepted (supersedes the key editor of ADR-218 and ADR-049)

## Context
`/platform/push` (ADR-218) asked the platform team to create a VAPID key pair in
their browser, showed both keys in text fields and saved the private key in
plain text. ANR, the vendor, read it as a code that had to be sent to every
member (2026-10-29), and a screenshot of the page showed the private key. The
help text also said `WEB_PUSH_*` environment variables win, while `PushConfig`
let the stored row win. gitops sets no `WEB_PUSH_*` at all.

Nobody needs to see or type these keys. Browsers fetch the public key from
`/api/notifications/push-config` when a person taps «Επίτρεψε ειδοποιήσεις» in
the bell panel; the private key only ever signs pushes on the server.

## Decision
- **The server makes the pair.** On first use (`PushConfig.config/0`) with no
  usable pair stored, the API generates a P-256 pair (`Domain.VapidKeys`) and
  stores it. `notification_push_settings` is a real singleton (unique
  `singleton` column) and the write takes a row lock, so replicas starting
  together keep one pair. `config :palee, :web_push_auto_keys` (off in tests).
- **Encrypted at rest.** The private key lives in
  `vapid_private_key_encrypted` (`EncryptedBinary`, ADR-161). A value the
  current `DATA_ENCRYPTION_KEY` cannot read loads as `nil` and is replaced by a
  fresh pair, like a first start.
- **Server env wins.** `WEB_PUSH_PUBLIC_KEY` + `WEB_PUSH_PRIVATE_KEY`
  (`config :palee, :web_push_server_keys`) override the stored pair, and
  `WEB_PUSH_SUBJECT` overrides the stored contact. The console then shows
  «from the server» and refuses to change them (`push_managed_by_server`).
  The contact falls back to `config :palee, :web_push_default_subject`
  (`mailto:alerts@palee.app`).
- **The console shows status only.** `GET /api/platform/push-settings` returns
  `enabled`, `source` (palee/server/none), the contact and its source,
  `keys_created_at`, the number of browser subscriptions and the last
  delivered push. It never returns a key. `PATCH` accepts only `vapid_subject`
  (normalised server-side: a plain email gets `mailto:`, anything other than
  `mailto:`/`https:` is `invalid_push_contact`, shown under the field).
- **Replacing the keys is the one rare action**, under «Για προχωρημένους»,
  with an inline confirmation naming how many devices stop.
  `POST /api/platform/push-settings/rotate` makes a new pair and removes every
  browser subscription, which can never be delivered with the old key.
- **Devices heal themselves.** On every app load the web client compares the
  key its subscription was made with (`options.applicationServerKey`) to the
  current public key; on a mismatch it deletes and unsubscribes the old one
  and, where the person already allowed alerts, subscribes again with no
  prompt.
- **Cross-user figures through SECURITY DEFINER.** Browser subscriptions are
  personal rows under forced RLS, so `palee_web_push_device_stats()` and
  `palee_forget_web_push_devices()` (search_path pinned, no extension GUCs)
  answer only when `palee_acting_user_is_vendor()`.
- **Migration 20270320000000** drops the plaintext private key and clears the
  public key (the hand-made keys were on screen), removes subscriptions made
  with them and adds a partial index for the last delivered push.

## Rationale
Generating keys server-side removes the only manual step and the only place a
secret was shown. Env-first keeps gitops in control when someone wants that
(the same order as other provider credentials). Removing dead subscriptions and
self-healing clients make rotation safe without asking members to do anything.

## Alternatives Considered
- One «Turn on» button that makes the keys (option B in the mockup): one more
  step that can be forgotten, during which nobody gets alerts. Rejected by ANR.
- Keys only from gitops (option C): needs a Secret, SOPS and a restart for
  something the server can do alone. Kept as the override, not the default.

## Consequences
The first deploy makes a new pair; devices that allowed alerts subscribe again
on their next visit. Turning browser alerts off for the platform is no longer a
console action. Tests start with no keys (`web_push_auto_keys: false`).

## Implementation Notes
`Palee.Notifications.PushConfig`, `Domain.VapidKeys`, `Domain.PushContact`,
`Ports.PushKeyStore` / `EctoPushKeyStore`, `Commands.SavePushContact`,
`Commands.ReplacePushKeys`, `Queries.GetPlatformPushStatus`,
`PlatformPushSettingsController`; web `PlatformPushSettingsPage`,
`lib/vapid-key-match.ts`, `usePushNotifications`. Tests:
`platform_push_settings_controller_test.exs`, `PlatformPushSettingsPage.test.tsx`,
`vapid-key-match.test.ts`, e2e `box-settings-help.spec.ts`.
