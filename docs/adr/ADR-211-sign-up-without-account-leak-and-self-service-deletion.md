# ADR-211: Sign-up that does not reveal accounts, and self-service account deletion
Date: 2026-10-27
Status: Accepted

## Context
- **Sign-up leaked accounts.** ADR-187 let a repeated email at sign-up
  answer 409 `email_in_use` with `profile_count` and `profile_limit`. Anyone
  could check whether an address has a Palee account, and how many profiles
  it holds. Handles are public by design, so the handle availability
  endpoints stay as they are.
- **No self-service deletion.** People could not delete their own profile or
  account, which GDPR (Art. 17) requires. These paths existed:
  - vendor and admin deletes: `DeleteAdminUser` → `Identity.delete`, which
    refuses the last `:admin`;
  - the tenant purge and organization delete: `delete_tenant_scoped_user`,
    which keeps an account another business's records still hold;
  - the wellness erase (`EraseMyWellness`);
  - the secret-free account export (`AccountExport`).

  The accounting tables ADR-117 must keep (`memberships`, `finance_invoices`,
  `finance_credit_ledger_entries`, `finance_payment_reversals`,
  `finance_refund_receipts`) reference `users` with `ON DELETE CASCADE`. A
  plain profile delete would therefore wipe records the business must keep
  by law.

## Decision

### 1. Sign-up with an email that already has an account
- **Wrong password.** `POST /api/auth/register` with an email that already
  has a login, and a password that is not that login's, answers exactly like
  a new sign-up:
  - `201 {confirmation: "email_sent", email}`;
  - nothing is created and no session is issued (no `access_token`, no
    refresh cookie);
  - the fields still get every check a new sign-up gets
    (`Identity.validate_new_login/1`: handle rules, handle free, display
    name, password strength), in the same order;
  - the address's owner gets `:signup_attempt_existing` (category
    `:account`, at most 1 an hour and 3 a day, carries no token). The email
    says someone tried to create an account with this email, and if it was
    them, they can sign in to add a profile or reset the password. A
    throttled, suppressed or over-budget email changes nothing in the
    answer.
- **Right password.** The behaviour is unchanged: a profile is added within
  the limit and the session opens. A full login still answers
  `profile_limit`, because the right password proves ownership.
- **New email.** It answers `201 {access_token, confirmation: "email_sent",
  email}`. The verify-email change sends its link at the same moment, so
  "email sent" is true in both cases.
- **Same timing.** Both paths compute one password hash (the verify of the
  existing login's hash, or the new login's hash) and make a few reads plus
  one or two inserts.
- **Same screen in the web.** Every self-service sign-up shows one screen,
  `CheckInboxNotice`: "Check your inbox. We sent a link to x." with a
  **Continue** button.
  - For a new account, Continue goes on into the app (the recovery-codes
    offer, then the app).
  - For a known email, Continue goes to sign-in with the email filled in.

  So a genuine sign-up costs one extra tap, with no wait and no email round
  trip.
- **Scope.** The invitation paths (`register-member`, `register-admin`)
  keep `email_in_use` with the count. They need an invitation token, and
  another change owns `/set-admin`.

### 2. Self-service deletion (`Application.AccountDeletion`)
- **Scopes.** Settings › "Delete profile or account" offers two scopes:
  - `profile`: this profile. A login's only profile counts as the whole
    account.
  - `login`: the account (the ontology's Λογαριασμός) with all its
    profiles.
- **Request.** `POST /api/auth/account-deletion {scope, password,
  confirm_email?}` needs the current password. It has its own rate limit:
  10 a minute, keyed on the session and the IP.
  - **Verified email:** an `account_deletion` LinkTokens link (24 h) is
    emailed (`:account_deletion_confirm`, category `:security`). The token
    is in the fragment of `/account-deletion/confirm#token=…`, and the page
    acts only on a button press.
  - **Unverified email:** the person types the account's email address
    instead, and the deletion is scheduled at once. An emailed link would
    prove nothing more than the password, and the person may not be able
    to read that inbox.
- **Scheduled.** A request is scheduled 7 days ahead (`AccountDeletionPolicy`).
  At that moment:
  - every session of the profiles in scope dies (`security_version`
    bump);
  - a profile-scope deletion moves the login's "last used" profile, so
    email sign-in opens another profile;
  - `SecurityNotices.notify(:account_deletion_scheduled, account, %{scope,
    scheduled_for, undo_url})` carries the `account_deletion_undo` link
    (new LinkTokens purpose, valid until `scheduled_for`).
- **During the grace:**
  - signing in to a covered profile, with the right password only, answers
    403 `account_deletion_scheduled` with `scheduled_for`;
  - switching to the profile is refused, and the profile is left out of
    the profile list;
  - the sign-in form offers "Undo the deletion and sign in"
    (`/account-deletion/undo-sign-in`, the same credentials);
  - the emailed undo link (`/account-deletion/undo`) also cancels it;
  - another profile of the same login can cancel it from Settings.
- **Execution.** `ExecuteAccountDeletionsJob` runs hourly at minute 19. It
  is a sweep, so an undo needs no job to be cancelled. For each profile:
  - if the profile appears in the retained accounting tables
    (`palee_user_has_retained_records`), or a `RESTRICT` reference still
    needs it, it is **anonymised in place**:
    - handle `deleted.<random>`, name "Deleted account";
    - no avatar, search text, zone or tours;
    - versions bumped;
    - moved to a tombstone login nobody can sign in to;
  - every other profile is **deleted**, with everything that cascades
    from it.

  The login goes once it has no profiles left. The request row is then
  deleted, so no history of the person remains. `:account_deleted` is
  notified with `to:` set to the address captured before the delete.
- **Sole owner.** A sole active owner of an active business cannot delete
  that profile (409 `sole_owner` with the business names). They give it
  another owner, or the platform team closes it. `palee_sole_owned_organizations`
  checks this both at the request and again at execution. If the person
  becomes a sole owner during the grace, the deletion waits, is still
  undoable, and is logged.

## Rationale
- **Why some leak remains.** Answering a known email with the very same
  response is the standard fix, but it only works fully when every new
  sign-up also waits for an email link. That would put an inbox round trip
  in front of every new member at the gym desk, against the vision's
  frictionless start. Instead the body, the status code, the screen and
  the timing match, and only what a new account must have (its session)
  differs.
- **A sweep, not one job per deletion.** A sweep with a request row is
  simpler than one scheduled Oban job per deletion. An undo is a row
  delete, and a missed run catches up.
- **Anonymise, not delete, the kept records.** Anonymising the profile row
  in place keeps every accounting foreign key valid without touching the
  immutable finance rows (`finance_refund_receipts_immutable`). Moving
  them to a tombstone profile would have needed exactly that. The business
  keeps its invoices, under "Deleted account".

## Alternatives Considered
- **Make every new sign-up wait for the email link before getting a
  session.** It closes the leak completely but adds friction for every
  real member. Rejected for the self-service form.
- **Keep the 409 but drop the count.** This still says "an account exists".
  Rejected.
- **Show a different screen for the known email** (no Continue, or a
  sign-in link right away). The difference is visible at a glance, over a
  shoulder. Rejected for one identical screen.
- **Reassign retained finance rows to a shared tombstone profile.** Refund
  receipts are immutable, and the update needs RLS bypass over every
  finance table. Rejected.
- **A per-context erase of every personal table before deletion.** Hard
  deletion already cascades everything for profiles with no retained
  records. For retained ones it would need a generic delete across about
  130 cascading tables with unknown side effects. Deferred (see
  Consequences).

## Consequences
- **Residual leak (documented).** A client that reads the raw response can
  tell a new account (it gets `access_token` and a `Set-Cookie`) from a
  known email (it gets neither). In the web UI the two differ only after
  Continue: the app, or the sign-in form. The leak is bounded:
  - the auth endpoints are limited to 10 requests a minute per IP;
  - every probe is noisy for the owner, who gets either the verification
    email of an account the prober now holds, or `:signup_attempt_existing`;
  - a probe of a new address creates a real account in the prober's name
    on someone else's email, unverified until its owner clicks.
- **Other residual leaks:**
  - The business sign-up (`/register/business`) shows the same
    check-your-inbox step for a known email. A new email still goes
    straight to "Your account is ready" with the demo business, so that
    form leaks after submit.
  - The invitation paths still answer `email_in_use` with the count.
- **Anonymised profiles keep their activity rows** (workouts, posts,
  messages, wellness) linked to an anonymous id with no name, handle,
  email, avatar or login. Follow-up: an erase of personal-only tables for
  anonymised profiles, context by context, starting with wellness (reusing
  `Wellness.erase`), journal, messaging and community posts.
- **Sole owners of coach practices or demo businesses** are also blocked
  until the business is closed. There is no self-service "close my
  business" yet; the message asks them to contact the platform team.
- **Handover to the security-notices change.** The events
  `:account_deletion_scheduled` and `:account_deleted` are added to
  `SecurityNotices` there, with their templates
  (`:security_account_deletion_scheduled`,
  `:security_account_deleted`). This change calls `notify/3` only when the
  event is listed, so it works before and after that merge. The meta is:
  - `scheduled`: `scope`, `scheduled_for`, `undo_url`;
  - `deleted`: `scope`, `to`.
- **A new platform table, `account_deletions`**, without RLS (like
  `logins`): one open request per login, gone with the login or once
  carried out or cancelled. There are also two `SECURITY DEFINER`
  functions with a pinned `search_path`.

## Implementation Notes
- **Code:**
  - `Application.SignUpWithExistingEmail`; `RegisterUser` routes
    `{:email_in_use, _}` to it (invitation paths untouched);
  - `Application.AccountDeletion`; `Identity.Domain.AccountDeletionPolicy`;
  - `Identity.AccountDeletion` (schema), its port, facade and the adapter
    `Infrastructure.Identity.EctoAccountDeletionStore`;
  - `Workers.ExecuteAccountDeletionsJob`;
  - `PaleeWeb.AccountDeletionController`;
  - `LoginUser.authenticate/1`, plus the scheduled-deletion guard in
    `LoginUser.call/1` and `AccountProfiles.list/switch`.
- **Routes:**
  - `GET|DELETE /api/auth/account-deletion` (session);
  - `POST /api/auth/account-deletion` (session, credential rate limit);
  - `POST /api/auth/account-deletion/{confirm,undo,undo-sign-in}`.
- **Migration** `20261224180000_account_deletions`.
- **Emails:**
  - kinds `:signup_attempt_existing` and `:account_deletion_confirm`;
  - their strings are in a gettext domain of their own,
    `account_lifecycle`, for all 12 locales, to keep merges with
    `emails.po` trivial. `scripts/validate_gettext_catalogs.mjs` and
    `AccountLifecycleTemplatesTest` check it;
  - new LinkTokens purpose `account_deletion_undo` (7 days, replaces).
- **Web:**
  - `CheckInboxNotice` (namespace `signupInbox`), shared with the
    verify-email change;
  - `DeleteAccountSection` (`/me/settings#delete-account`, namespace
    `accountDeletion`);
  - `AccountDeletionLink` (`/account-deletion/confirm`,
    `/account-deletion/undo`);
  - `signUp()` now returns `{email, user | null}`.
