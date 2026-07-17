# ADR-057: Opaque one-time tenant invitations
Date: 2026-07-18
Status: Accepted

## Context
New users and administrators must join the correct organization without selecting it from a directory. Invitations must expire, be redeemable once, convey the intended membership role, support manual distribution initially, and later support verified email or OTP delivery.

## Decision
Generate cryptographically random opaque invitation tokens with at least 128 bits of entropy. Store only a deterministic digest for lookup; store organization, role, issuer, expiry, redemption, and revocation state in the invitation row. The clear token is returned once. Redemption locks the invitation and atomically creates or attaches the identity, creates the membership, and marks the invitation redeemed.

The token determines organization and role. Clients request token generation through authorized application services but never possess a signing key. Live generation is the default; audited batches may use the same persisted model later. ADR-054's shared admin code is superseded for tenant onboarding.

## Rationale
Opaque database-backed capabilities disclose no tenant identifier and support one-time use, revocation, auditing, and role binding. Stateless signatures still require persistent redemption state, so they add complexity without removing the database lookup.

## Alternatives Considered
Deterministic or reversible tenant codes were rejected as predictable and difficult to revoke. Reusable organization codes were rejected because one disclosure grants indefinite enrollment. Stateless JWT/PASETO invitations were rejected because one-time redemption and revocation still need a database record. Pre-generated inventory was rejected as the default because unused codes enlarge the exposure window.

## Consequences
Possession of an unexpired token authorizes its intended registration, so tokens must be short-lived, rate-limited, redacted from logs, and displayed once. Manual delivery remains an initial operational constraint; automated verified delivery is tracked as TD-034.

## Implementation Notes
To be completed after implementation.
