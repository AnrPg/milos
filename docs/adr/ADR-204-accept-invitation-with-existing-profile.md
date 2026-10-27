# ADR-204: An existing profile accepts an owner or staff invitation; an email with an account is told what to do
Date: 2026-10-27
Status: Accepted

## Context
ADR-187 lets one account (one email and one password) hold up to 3 profiles. The invited sign-up
(`/set-admin`, `POST /api/auth/register-admin`) runs through `RegisterProfile`: a new email creates
an account, and an email that already has one gets a new profile only when the typed password is
that account's password. Any other password answers 409 `email_in_use` with the profile count.

On 2026-10-27 ANR invited the vendor's own email as owner of a test gym and signed up on `/set-admin`
with a new password (`1234`). The server answered 409 (`profile_count: 1`). The page showed the raw
"already has accounts" text, with no hint that the account's password was needed and no way to
use a profile the person already has. A signed-in visitor (since ddb931aca8) could only sign out
or leave.

## Decision
1. **Accept with the signed-in profile.** `POST /api/auth/accept-invitation` (authenticated,
   invitation rate limit) runs `Application.AcceptInvitation`. It uses the same redemption as
   `/memberships/redeem` (`RedeemRegistrationInvitation`: F-10 email binding, ADR-184 demo gate,
   coaching start) and then gives the profile the surface role the invited sign-up would get.
2. **Surface role in one place.** `Application.InvitationAccountRole` maps an invitation role to
   the account role (staff → `admin`, athlete → `athlete`, else `member`), as ADR-095 does. An
   existing profile is only ever lifted (member → athlete → admin), never lowered.
   `RegisterInvitedUser` uses the same module.
3. **A role change keeps the browser signed in.** Changing the role bumps `security_version`,
   which ends the profile's sessions. So the endpoint returns a new token pair and refresh cookie
   when the role changed (`access_token` and `user`), and `null` for both when it did not.
4. **`/set-admin` explains the 409.**
   - The password help says to type the account's password when the email already has one.
   - A 409 `email_in_use` or a 422 `profile_limit` shows "This email's account already has N of 3
     profiles", with links to *Sign in to accept* (`/login?next=/set-admin?token=…`) and *Forgot
     the password?*.
   - Signed in, the page offers *Accept as @handle* first, then *Sign out and continue* (to make a
     separate profile), then *Stay signed in*.
5. **OpenAPI.** `register-admin` and `register-member` now document 409 `email_in_use` and 403
   `invitation_email_mismatch`.

## Rationale
- The password check stays the proof that the person owns the account (ADR-187). This ADR adds
  the missing path and explains it; it does not loosen the check.
- A separate endpoint, not a change to `/memberships/redeem`: the member app (MyGymsCard,
  FirstRun) does not expect its session to change. Lifting the role there would sign people out.

## Alternatives Considered
- Let `register-admin` attach the invitation to an existing profile without a password: anyone
  holding the link could take over the email's account. Rejected.
- List the email's profiles on the 409 to choose one: this leaks which profiles an email holds
  (ADR-187 shows only the count). Rejected; the list is shown after sign-in.

## Consequences
- Permanently deleting a gym already deletes its invitations (`registration_invitations` FK
  `on_delete: :delete_all`). A test now pins it: the deleted gym's link stops working.
- Thread "Harden email-based account flows" (ADR-203) adds `mark_email_verified` at redemption.
  Hooking it into `RedeemRegistrationInvitation` covers this endpoint too.

## Implementation Notes
- Web: `acceptInvitation` in `api/auth.ts` and in the session provider, which adopts the new
  session when one comes back.
- Tests: `auth_controller_test.exs` (409 then a 201 with the right password, accept-invitation
  cases), `platform_organization_controller_test.exs` (invitations deleted with the gym),
  `invitation_account_role_test.exs`, `admin-registration-console.test.tsx`, and
  `e2e/set-admin-invitation.spec.ts`.
