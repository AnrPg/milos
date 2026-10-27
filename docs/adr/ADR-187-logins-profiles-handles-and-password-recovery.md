# ADR-187: Logins with up to three profiles, @handle + display name, and mail-free password recovery
Date: 2026-10-23
Status: Accepted

## Context
Registration failed with "email has already been taken": every account needed its own email
(`users_email_unique_index`), while ANR wants one email to hold up to three accounts. Nicknames were
unique and doubled as the shown name, which forced people with common names into odd spellings. There
was no password recovery at all, and there is no mail service (no external services allowed).

## Decision
- **Login and profiles.** A `logins` row owns the email (unique, case-insensitive), the password hash and a
  `security_version`. `users` stay the profiles (every foreign key keeps pointing at them) and gain
  `login_id`; a login holds at most three profiles (application check + `users_profile_cap` trigger).
  A token's `sv` is user + login versions, so a password change signs out every profile.
- **@handle + display name.** The unique handle is Latin-only lowercase (`a–z 0–9 . _`, 3–30), typed
  scripts are transliterated; the display name is free (any script, emoji, 1–50, no invisible/bidi
  control characters). The columns keep their historical names (`nickname` = handle,
  `display_nickname` = display name) because SQL functions and views use them; Ecto maps them. A hidden
  folded `search_text` (name, its transliteration, handle) backs search. A handle changes at most every
  14 days and the old one stays reserved for its owner for 30 days.
- **Sign-up.** No email verification for the MVP; the form explains that the email must be one the person
  can open. A repeated email gets only the count of profiles (never which); more profiles are added
  after signing in. (ADR-211: the public sign-up no longer tells even that; it answers a known email like a
  new one.)
- **Password recovery without mail.** A request (email or @handle, always answered "sent") reaches the
  vendor, the owner/admin/front desk of the person's boxes and their coach
  (`palee_password_reset_handlers`, a definer function since the links live in tenant tables). The first
  opener claims it (30-minute idle lapse, vendor can take over), confirms identity off-app and mails a
  one-time 24-hour link from their own mailbox (mailto + copy). Only the token hash is stored. Closed
  requests are deleted; expired links stay listed as "Expired". Handlers can hide entries for
  themselves. Every step goes to `password_reset_log`, readable by the vendor only. Ten optional
  one-time recovery codes are the self-service fallback.

## Rationale
Keeping `users` as profiles avoided rewriting hundreds of foreign keys and RLS policies. Handle +
display name is the pattern people know from Instagram/Telegram/Discord: unique and typeable for
mentions and sign-in, free for how they are shown. The handler-based recovery uses the trust that already
exists (the gym knows its members) and needs no infrastructure.

## Alternatives Considered
- Unique email per account with `+tags`: confusing, and gmail-only.
- Non-unique nicknames disambiguated by avatar: fragile and unsearchable.
- External mail provider: ruled out (no external services); an in-cluster mail sender (gen_smtp is already
  a dependency) is the follow-up.

## Consequences
- After the MVP, an own mail service sends verification links at sign-up and reset links automatically;
  the handler flow stays as a fallback.
- 2026-10-27, ADR-213: sign-up now emails a verification link (ADR-203 outbox); the app stays usable
  while unverified, and the sign-up form says a confirmation link was sent. The "no email verification
  for the MVP" decision above is superseded on that point.
- Display-name renames propagate to notification snapshots only when the old name is no longer used by
  any profile (`palee_propagate_notification_nickname` now checks display names).

## Implementation Notes
Migrations 20261203100000 (logins + profiles), 20261203110000 (recovery), 20261203120000 (propagation).
API: `/api/auth/{handle-available,handle-suggestion,profiles,switch-profile,recovery-codes,
password-reset-requests,password-reset,password-reset/recovery-code}`, `/api/password-resets/*`,
`/api/platform/password-reset-log`.
