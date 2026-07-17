# ADR-054: Code-Gated Admin Registration
Date: 2026-07-18
Status: Accepted

## Context

The approved registration model originally prevented public creation of admin
accounts and required an existing admin to promote a member or athlete. The
product owner explicitly requested a dedicated `/set-admin` registration page
that can bootstrap an admin account only when the registrant supplies the exact
owner-issued code.

The browser cannot be trusted to enforce this gate. The flow must also preserve
the existing auth rate limit, password hashing, refresh-cookie security, token
rotation, contract-first API, and Identity persistence boundary.

## Decision

Add a separate `POST /api/auth/register-admin` contract and `/set-admin` page.
The backend compares the submitted code with the configured admin registration
code using a constant-time pure Identity domain policy, then forces the created
role to `admin`; the browser never supplies or chooses the role.

The owner-requested default code is configured server-side as `DEY48keGE` and
may be replaced at runtime with `ADMIN_REGISTRATION_CODE`. The endpoint shares
the existing authentication rate-limit pipeline and issues the same short-lived
access token plus rotating HttpOnly refresh cookie as standard registration.

## Rationale

A distinct endpoint keeps ordinary self-registration restricted to members and
athletes while making the exceptional trust boundary explicit and auditable.
Server-side validation prevents bypassing the code by calling the API directly,
and forcing the role avoids accepting client-controlled privilege fields.

## Alternatives Considered

Client-only code validation was rejected because browser code and requests are
fully user-controlled. Extending the ordinary registration endpoint with an
optional admin role was rejected because it would weaken the public contract
and make privilege creation less visible. Requiring direct database insertion
was rejected because it bypasses Identity validation, hashing, and session
issuance workflows.

## Consequences

Anyone who learns the configured code can attempt admin registration, so the
endpoint remains rate-limited and operators can rotate the runtime value. The
fixed owner-requested default is suitable only for the explicitly accepted
deployment policy; changing it does not require a code release when the runtime
environment variable is set.

## Implementation Notes

Identity now has a dedicated admin registration changeset and store callback;
ordinary registration continues to reject the admin role. The application
service validates the code before persistence, cleans up the user if token
issuance fails, and returns the normal secure browser session. OpenAPI and the
generated TypeScript client include the new contract. Focused domain and
controller tests cover exact-code acceptance, rejection without persistence,
admin role creation, and secure refresh-cookie issuance.
