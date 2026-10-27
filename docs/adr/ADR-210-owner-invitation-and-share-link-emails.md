# ADR-210: Owner invitation email on the outbox; share links by email
Date: 2026-10-27
Status: Accepted

## Context
ADR-203 put corporate invoices on the transactional email outbox. The owner
invitation still went out synchronously, in English only, and had two problems:
- the raw setup code was in the email body next to the link;
- a retried request sent a second email, and the vendor console could not
  tell whether the email had gone out.

Members also share three kinds of link: a guest pass for an event (ADR-153,
ADR-185), a check-in buddy invite link (ADR-160) and «Φέρε φίλο» (ADR-156).
They share them only through the phone's share sheet or by copying. Someone
whose friend has only an email address had no way to send it.

## Decision
### Owner invitation (`:owner_invitation`, category `account`)
- `POST /api/platform/organizations/:id/invitations/email` with `{email, token,
  locale?, resend?}`. It finds the invitation by the token's digest. The
  invitation must belong to the organization in the path, be owner or admin,
  and still be redeemable. Otherwise: `invalid_invitation`. A bound invitation
  is emailed only to its own address (`invitation_email_mismatch`).
- The email is queued, the `organization_invitation_emailed` audit event is
  recorded, and the invitation is marked as emailed
  (`Organizations.mark_invitation_emailed/2`, ADR-209). All three happen in
  one transaction: a refused enqueue (suppressed, throttled) records nothing.
- Idempotency key `owner_invitation:<invitation id>`. Sending again returns the
  first message. `resend: true` queues `owner_invitation:<id>:resend:<n>`,
  which is still subject to the outbox's per-address throttle (account: 60 s,
  10 a day).
- The answer is `202 {delivery: {id, status, attempts, inserted_at,
  scheduled_at, sent_at}}`. `GET
  /api/platform/organizations/:id/invitations/:invitation_id/email` lists the
  invitation's deliveries, newest first. It never shows the address, the
  subject or the provider's error.
- Language: the vendor's pick, else the business's default locale, else Greek.
  The console has a language picker next to the send button, set to the
  business's default locale.
- The email has the setup link only. The setup code stays on the vendor
  console as the manual fallback.
- It is not demo gated: it is the platform's own mail, and the vendor sends it
  before the business goes live.
- Opening the emailed link and signing up with the same address marks the
  login's email as verified. ADR-209 does this in `RedeemInvitation`: the
  invitation is bound, the address matches and `emailed_at` is set.

### Share link by email (`:share_link`, category `transactional`)
- `POST /api/me/share-links/email` with `{link: guest_pass | buddy_invite |
  referral, token, to}`.
- The server rebuilds the URL from what the member holds and never accepts a
  URL:
  - a guest pass token must be signed by the sender;
  - a buddy invite token must be the sender's own and still pending;
  - a referral code must be the sender's own.

  Otherwise: `share_link_invalid` (404).
- Checks, in order:
  1. A mock person never sends (`business_not_activated`).
  2. The sender's own email is verified (`share_link_sender_unverified`, 403).
  3. At most 10 share emails per sender in a rolling 24 h
     (`share_link_daily_limit`, 429). The count is read from the outbox through
     the key prefix `share_link:<sender id>:`.
  4. The outbox checks:
     - the recipient is not suppressed;
     - its per-recipient throttle for this kind (5 a day from all senders
       together);
     - the demo gate: a guest pass or referral carries its business's
       `organization_id`.
- Idempotency key `share_link:<sender>:<kind>:<digest of kind, link and
  address>`. The same link to the same address goes out once.
- Content: the link, the sender's display name and a line saying "if you don't
  know them, ignore this email". There is no note field. A display name that
  reads as a link or an address shows as `@handle` instead. The email is in the
  sender's language. The `transactional` category lets the deliverability work
  (List-Unsubscribe) apply.
- Web: one quiet "Send by email" link in each existing share sheet (the guest
  pass sheet, the check-in buddy invite link, the «Φέρε φίλο» card). It opens
  an address field. There is no new block.

## Rationale
- The outbox gives retries, the budget, suppression and a status the console
  can show. The key per invitation makes a retried request harmless.
- Rebuilding share links on the server means the endpoint cannot be used to
  mail an arbitrary URL in Palee's name.
- Per-sender, per-recipient and verified-sender limits together keep this from
  becoming a spam relay at the cost of a free plan's 300 emails a day.

## Alternatives Considered
- **A setup link through `LinkTokens`.** The invitee usually has no login, and
  `email_link_tokens.login_id` is required. The invitation token is already
  hashed, single use and short lived.
- **A personal note in the share email.** It turns the feature into an
  open-text mailer to strangers. Rejected.
- **A new per-sender counter table.** The outbox already stores every send
  under a sender-prefixed key, so no migration is needed.

## Consequences
- The vendor's raw token passes through the API once more (in the email
  request). It is never stored or logged; only its digest is used.
- Translations live in their own gettext domains, `owner_invitations` and
  `share_links`, for all 12 locales. `LinkEmailsTest` checks they are complete.
- `share_link` counts are read with a prefix scan of one sender's keys,
  bounded by 10 a day.
- Follow-up: PT squad invites could use the same endpoint as a fourth
  `link` kind.

## Implementation Notes
- Code:
  - templates: `lib/palee/email/templates/{owner_invitation,share_link}.ex`
  - pure rules: `lib/palee/email/domain/share_link_policy.ex`
  - send: `lib/palee/organizations/commands/send_owner_invitation_email.ex`
  - share links: `lib/palee/application/share_link_emails.ex`
  - controllers: `ShareLinkEmailController`, `PlatformOrganizationController`
- `Palee.Organizations.Emails.OwnerInvitationEmail` (the Swoosh builder) is
  removed.
- Provisioning and platform invitation responses now include the invitation
  `id`. The console uses it to read delivery status.
- The provisioned "owner" invitation has role `admin` (ProvisionOrganization),
  so its email says "admin". An `owner` invitation says "owner".
- Web: `components/share/SendLinkByEmail.tsx`, messages namespace
  `ShareByEmail`.
