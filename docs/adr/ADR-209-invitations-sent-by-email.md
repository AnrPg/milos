# ADR-209: Client and staff invitations sent by email
Date: 2026-10-27
Status: Accepted

## Context
A box invites clients and staff with one-time registration invitations
(ADR-099, ADR-186). Until now the app only made a link for the inviter to copy
or put into a `mailto:`. Binding an invitation to an address (F-10) only
checked that the redeeming account held that address. Nothing checked that the
person could read it: an account registered with someone else's address could
use a link that had leaked. TD-034 asked for invitations to be delivered by
email, with delivery status, retry, abuse controls and recovery. ADR-203 gave
the outbox for that.

## Decision

### 1. Send by email
- The invite dialog has one optional email field. With an address, the button
  says «Send invitation». The request sends `send_email: true` and
  `email_locale`.
  - The language picker (`ui/Select`) defaults to the box's language
    (`organization_settings.default_locale`).
  - Without an address, the dialog makes a link to copy, as before.
- `Application.InvitationEmails.send/2` does three things in one transaction
  (`Organizations.transaction/1`):
  1. It issues the invitation, bound to the address.
  2. It stores the address encrypted (`intended_email_encrypted`,
     `EncryptedBinary`), with `email_locale` and `emailed_at`.
  3. It enqueues `:organization_invitation`, category `transactional`, with
     `organization_id` and the key `organization_invitation:<invitation id>`.

  When the outbox refuses the email, no invitation is left behind. The
  refusals are `invalid_address`, `suppressed`, `throttled`, and `not_live`,
  which answers as `business_not_activated`.
- The token of an emailed invitation is **never returned** to the inviter, so
  it exists only in the email.
- The email carries:
  - the box's brand name and the inviter's display name;
  - the roles, and the branches for staff;
  - the expiry, in the box's time zone;
  - a button to `<public url>/invite#token=…`.

  The token sits in the fragment, so it reaches no server log and no
  `Referer` header.
- The copy lives in its own gettext domain, `invitation_emails`, in all 12
  API locales. The Greek uses the formal register and puts the box name in
  « ».
- Throttle: one address gets at most 5 invitation emails a day, at least
  2 minutes apart, from any box.

### 2. Demo gate
- A box in demo mode already cannot issue invitations (ADR-184,
  `:invite_people`). The outbox's `:send_outside` gate repeats the check for
  the email.
- The web shows the reason before anyone types: a notice in place of the
  form while `activation` is `demo`.

### 3. Delivery status, resend, revoke
- `GET /invitations` adds `email`, `email_locale` and `delivery_status` to
  each emailed invitation. `InvitationEmailPolicy.delivery_status/2` maps the
  outbox's latest message for the key:

  | Outbox state | Shown as |
  |---|---|
  | `queued` or `deferred` | `queued` |
  | `sent` | `sent` |
  | `sent`, address suppressed since | `bounced` |
  | `failed` | `failed` |
  | `suppressed` | `suppressed` |

  The suppression is checked again when the list is read, so a bounce
  webhook (ADR-203 follow-up) makes a sent invitation show `bounced`.
- `POST /invitations/:id/resend` **re-issues** the invitation in one
  transaction:
  1. It revokes the old invitation, so its link stops working.
  2. It issues a new one with the same roles, the same branches (archived ones
     drop out), the same coach, the same language and the same lifetime.
  3. It emails the new link.

  Re-issuing is safer than mailing the same token again: a link that leaked
  from an earlier email dies. The throttle above limits resends. A refused
  email rolls everything back, and the old invitation stays.
- Revoke works as before. The emailed link of a revoked invitation opens a
  page saying the box revoked it: `inspect` answers `invitation_revoked`
  (410), but only to the holder of the token. Other states still answer
  `invalid_invitation`.

### 4. Bulk invite
- `POST /invitations/bulk` takes `emails`, a list or pasted text/CSV, plus
  the same role, branch, lifetime and language fields.
- Addresses are split, lower-cased and deduplicated. Values that are not
  addresses come back in `skipped`. Each address gets its own invitation and
  email, each in its own transaction. The answer lists a result per address:
  `queued` with `invitation_id`, or an error code.
- Limits (`InvitationEmailPolicy`, overridable with
  `config :palee, :invitation_email_limits`):
  - at most 200 addresses per request (`too_many_invitation_emails`, 422);
  - per rolling 24 h, at most 300 emailed invitations per box and 200 per
    inviter (`invitation_email_cap_reached`, 429).

  The caps count `registration_invitations.emailed_at`, using two partial
  indexes. A request that would pass a cap is refused whole.
- Telemetry, with no address in any event:
  - `[:palee, :invitations, :emailed]`, with `%{count}` and
    `%{organization_id, mode}`, mode `single`, `bulk` or `resend`;
  - `[:palee, :invitations, :cap_reached]`.
- The ADR-203 global budget still applies. Past it, emails are deferred to
  the next UTC day, never dropped.

### 5. Binding: a verified address, or the emailed link
`InvitationEmail.redemption_proof/3` decides, after the address match (F-10):
- **Emailed** (`emailed_at` set):
  - The matching account may redeem: the token only went to that inbox.
  - On success the redemption calls `Identity.mark_email_verified(login_id,
    email)`. This works for an account created in the same request
    (`register-member`, `register-admin`) and for an existing one.
- **Bound by a box but not emailed** (`email_verification_required`, set when
  an invitation is issued with `intended_email` from a tenant): the login's
  email must be verified, else `invitation_email_unverified` (403). The
  invitation is not consumed.
- **Platform owner invitations** (ADR-089) keep the plain match unless
  `Organizations.mark_invitation_emailed/2` marks them. The owner flow calls
  it when it mails them. The vendor, a trusted party, may still see that
  token.
- An account whose email differs from the bound address gets
  `invitation_email_mismatch` (403). The message never shows the bound
  address.

### 6. The `/invite` page
- It reads the token from the fragment, or from `?token=` for older links,
  and inspects it.
- It shows the box, the role, the expiry, and a line saying the invitation
  is for one email address.
- Signed out, it offers «Create an account» and «I already have an account».
  - Create an account goes to `/register` or `/set-admin` with the token in
    the fragment.
  - Before signing in, the token is kept in `sessionStorage`, so the sign-in
    redirect never puts it in a URL.
- Signed in, it offers «Join», which redeems the invitation.
- The page names each failure: revoked, not valid any more, another email
  address, or an address not confirmed yet.
- `/register?token=` and `/set-admin?token=` keep working, and also read
  `#token=`.
- `/join/:slug` join links are unchanged.

## Rationale
- With the token only in the email, the link is the proof of the inbox,
  like ADR-203's link tokens. No second token is needed.
- `Palee.Email.LinkTokens` needs a login (`email_link_tokens.login_id` is NOT
  NULL), and most invitees have none yet. The invitation token already gives
  the same guarantees: 32 random bytes, only its SHA-256 at rest, single use,
  5 minutes to 7 days.
- The encrypted address is what makes "Resend" and the status list possible
  without asking the inviter to type the address again.

## Alternatives Considered
- **A `LinkTokens` proof next to the invitation token, with copy-link kept for
  emailed invitations.** This needs loginless link tokens, a change to
  ADR-203's table, and a link with two secrets. Copy-link is still there for
  invitations without an address. Rejected.
- **Mailing the same token again on resend.** A leaked earlier email would
  stay valid. Rejected in favour of re-issuing.
- **A per-box counter table for the caps.** The `emailed_at` column already
  holds the facts. Rejected.

## Consequences
- An invitation a box binds to an address without emailing it now needs a
  verified address. The web always emails when an address is entered, so
  only API clients that send `intended_email` alone are affected.
- `registration_invitations` holds the encrypted address of emailed
  invitations. It is tenant data, purged with the box (ADR-117).
- The pending list reads the outbox once per emailed invitation (at most 100
  rows).
- TD-034 is resolved.

## Implementation Notes
- Migration: `20261224160000_invitations_sent_by_email.exs`.
- Code:
  - domain: `Organizations.Domain.InvitationEmailPolicy`,
    `InvitationEmail.redemption_proof/3`
  - queries: `Organizations.Queries.EmailedInvitations`
  - application service: `Application.InvitationEmails`
  - template: `Email.Templates.OrganizationInvitation`
- Web:
  - `components/invites/InviteClients.tsx` (send, bulk, status, resend)
  - `components/invites/InviteRedeem.tsx` and `app/invite/page.tsx`
  - messages namespace `InviteEmail`
