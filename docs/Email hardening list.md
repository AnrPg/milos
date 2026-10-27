# Email hardening list

Oct 27, 2026 · @ANR

## Summary

The app sends only two emails today (the gym owner invitation and corporate invoices); every other account flow still assumes there is no mail, so 20 items need hardening, 6 of them urgent. Checked against `main` at fbb943e on 27 Oct 2026.

The six urgent ones, because an unverified email is trusted somewhere today:

1. **Verify the email** at sign-up and on change (`logins.email_verified_at` exists but nothing sets or reads it).
2. **Corporate email-domain plans** enroll anyone whose account email ends in the company domain. Since emails are unverified, typing `x@company.com` at sign-up gets a seat the company pays for.
3. **Email-bound invitations** (staff, members, owners) compare the typed email, not a proven one.
4. **Automatic reset link by email**, keeping the handler flow as the fallback (ADR-187 promise).
5. **Email change** happens instantly with the password, sends nothing to the old address and keeps every session alive.
6. **Security notices by email** (password changed, email changed, recovery code used, codes regenerated, new sign-in).

## Account flows

The login (one email, one password, up to 3 profiles) is the unit that gets verified; every row below works on the login, not the profile.

| # | Flow | Today | Gap | Recommended hardening | Priority |
| --- | --- | --- | --- | --- | --- |
| 1 | Email verification at sign-up | No verification (ADR-187 MVP); only a notice that the email must be one you can open | Typos and fake emails are accepted; nothing downstream can trust the email | Send a one-time link (hash stored, 24 h, single use) on sign-up; set `email_verified_at`. Let people use the app meanwhile, with a banner and a resend button; gate only the things that trust the email (rows 12, 13, corporate seats, sending email to that address) | Urgent |
| 2 | Password reset | Request goes to handlers (vendor, box staff, coach), who mail the link by hand via mailto; recovery codes as fallback | Slow, needs a human, handlers see the person's email | If the email is verified, mail the reset link automatically (same 24 h single-use hashed token). Keep the handler queue only for unverified or lost inboxes. Same "if an account exists, we sent it" answer either way | Urgent |
| 3 | Email change | Instant with current password; no mail to old or new address; sessions stay | A stolen session plus a known password moves the account to a new inbox silently | Keep the old email until the new one clicks a link; notify the old address with a "this wasn't me" link that reverts and locks; bump `security_version` on completion | Urgent |
| 4 | Security notices | Only an in-app notice after a reset | The person never hears about a takeover attempt if they don't open the app | Email on: password changed, email change requested and done, recovery code used, codes regenerated, all sessions signed out, new profile added to the login. Never include the secret itself | Urgent |
| 5 | New sign-in alert | None | Silent account sharing or takeover | Email on a sign-in from a new device (device cookie or refresh-token family), with "sign out everywhere" link | Soon |
| 6 | Sign-up enumeration | A repeated email returns 409 `email_in_use` with the profile count | Anyone can test whether an email has an account | Once mail works: always answer "check your inbox"; to the existing owner, mail "someone tried to sign up, sign in to add a profile". Drop the count from the public answer | Soon |
| 7 | Reset request flooding | IP rate limit 10/min on `/api/auth/*`; one open request per login | With mail, one IP can mail-bomb a person or burn the Brevo quota | Per-login and per-email limits (e.g. 1 mail per 10 min, 5 per day), plus a global daily send budget below the Brevo plan cap | Urgent with row 2 |
| 8 | Reset link handling | Token sha256-hashed, 24 h, deleted on use; password change revokes all sessions | Good. Missing: link opened from a mail scanner may be pre-fetched | Keep the token in the URL fragment or require a click on the page (POST) before it is spent; shorten to 1 h for automatic links | Soon |
| 9 | Recovery codes | 10 codes, hashed, password needed to regenerate | No email when they are used or regenerated | Covered by row 4; also remind by email when 2 or fewer are left | Later |
| 10 | Account deletion | No self-service delete endpoint found | GDPR right to erasure; also needs a confirmation path | Delete from Settings with password plus an email confirmation link, 7-day grace with an "undo" link | Later |
| 11 | Business sign-up and conversion | Vendor queue, activation link per account | Business owner email not verified before activation | Require a verified email before the vendor can activate (row 1) | Soon |

## Invitations and links

Every invitation today is a token the sender copies or puts in a mailto; the app should send it itself, and a click on an emailed link should also count as proof of the inbox (set `email_verified_at`).

| # | Flow | Today | Gap | Recommended hardening | Priority |
| --- | --- | --- | --- | --- | --- |
| 12 | Gym invites clients and staff (roles, branches) | Token link, 5 min to 7 days, optional email binding by sha256 digest; copy link or mailto from Invite clients | App sends nothing; binding checks the email typed at sign-up, which is unverified; no delivery status or resend | "Send by email" from the app through the outbox (row 18); show sent / failed / bounced and a resend; an email-bound invite redeems only from a verified email or by clicking the emailed link; bulk invite by CSV later (TD-034) | Urgent |
| 13 | Vendor provisions a gym owner (`/set-admin`) | Already emailed (the only invitation that is), sent inside the request, English only, raw setup code in the body | No retry if Brevo hiccups; not in the owner's language; a second secret sits in the mail | Move to the outbox with retries; localize; drop the raw code (the link is enough, or show a short code only on a failure page); verify the email on first use | Soon |
| 14 | Business activation link (ADR-184) | Bound to one existing account; vendor shows it once and sends it by hand | Manual step; the account's email may be unverified | Email it automatically to the account's verified email; refuse to issue for an unverified one | Soon |
| 15 | Corporate email-domain plans | Seat offered and granted when the account email ends in the company domain | Anyone can type a company address at sign-up and take a paid seat | Require `email_verified_at` (or a fresh email confirmation link to that address) before the offer and the enrollment | Urgent |
| 16 | Partner perks (ADR-191) | Partners have no account; a signed short-lived link per perk QR | Fine for now; the partner portal (TD-191) will need sign-in | When TD-191 starts, sign partners in by emailed magic link, no password | Later |
| 17 | Guest passes, buddy invites, referrals, PT squads, event co-hosts | Signed or random share links, or in-app requests between accounts | None of these rely on email; they work as designed | Keep as is. Optional later: "invite by email" that just mails the same link through the outbox, rate-limited per sender | Later |

## Mail platform

All the rows above should go through one email port with an Oban-backed outbox, instead of each feature calling `Palee.Mailer.deliver` inside the request as the two current emails do.

| # | Piece | Today | Gap | Recommended hardening | Priority |
| --- | --- | --- | --- | --- | --- |
| 18 | Outbox and retries | Owner invite and invoices send synchronously; a failure returns an error, no retry | A Brevo timeout loses the mail; slow requests | An `email_messages` outbox row per mail (kind, recipient, locale, status, attempts, provider id), sent by an Oban worker with backoff; idempotency key per event so a retry never double-sends; one Email port in the domain, Swoosh adapter in infrastructure | Urgent (first) |
| 19 | Templates and language | Two hand-written HTML+text templates, English only | Members use 12 locales | One shared layout (Palee theme colours from `BrandPalette`, plain-text twin), strings in the existing locale files, sent in the person's `preferred_locale`; preview page in dev (`/dev/mailbox` exists) | Urgent |
| 20 | Deliverability and limits | SPF, DKIM and DMARC set in Cloudflare; SMTP with `tls: :always`; Brevo keys expire 26 Oct 2027 | No bounce or complaint handling; no send budget; certificate check of the SMTP TLS not pinned in config; key expiry only in memory | Brevo webhook for bounces and spam complaints marks the address undeliverable and stops further mail; daily budget alarm under the Brevo plan cap; set `tls_options` with `verify_peer`; a Grafana alert or calendar reminder before the key expiry; `List-Unsubscribe` on any non-security mail | Soon |

One open question: which Brevo plan is active. The free plan allows 300 emails a day, which a burst of sign-ups or invitations can use up.

## Earlier promises and suggested order

Four earlier decisions said "once there is mail", and the list above covers all of them:

- **ADR-187** (23 Oct): after the MVP, verification links at sign-up and automatic reset links, with the handler flow kept as a fallback (rows 1, 2).
- **TD-034**: automate tenant invitations through verified email links, with delivery status, retry, abuse controls and recovery (rows 12, 18, 7).
- **TD-184 (2)**: any channel that reaches people outside the business needs `GoLive.check(:send_outside)`, so a demo business never emails real people (applies to rows 12 and 17).
- **TD-083**: branded emails (row 19, one Palee theme, no per-gym branding as you decided on 21 Oct).

Suggested order, each step one PR:

1. Mail platform: outbox, Email port, shared localized layout (rows 18, 19).
2. Email verification and the gates that trust it: corporate seats, email-bound invites, business activation (rows 1, 15, 11).
3. Automatic password reset with per-login limits and the hardened link (rows 2, 7, 8).
4. Safe email change and security notices (rows 3, 4).
5. Send invitations from the app with status and resend (rows 12, 13, 14).
6. Sign-up enumeration, new sign-in alerts, bounces and budgets, account deletion (rows 6, 5, 20, 10).
7. Later: rows 9, 16, 17.

Tell me which rows to take (or "all, in this order") and I will start with step 1.
