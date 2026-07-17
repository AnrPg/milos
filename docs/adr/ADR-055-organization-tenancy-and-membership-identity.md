# ADR-055: Organization tenancy and membership-scoped identity
Date: 2026-07-18
Status: Accepted

## Context
Milos Training must serve independently operated gyms and coaching companies from one installation. The original model stores one global role on each user and assumes one gym owner, which cannot express isolated client administration, tenant-specific profiles, or one person participating in multiple organizations.

## Decision
Introduce `MilosTraining.Organizations` as a bounded context owning organizations, organization memberships, organization domains, organization settings, and registration invitations. `Identity` continues to own global authentication principals and credentials. Roles that authorize tenant behavior move to organization memberships; platform-operator authority remains separate from tenant roles.

Every tenant-owned record carries an `organization_id`. Cross-context registration and membership activation are orchestrated by `MilosTraining.Application.*` services using public context APIs and plain values.

## Rationale
Separating authentication from tenant participation supports consultants and coaches who work with multiple clients without merging client data or assigning contradictory global roles. A dedicated bounded context gives tenant lifecycle, membership authorization, and invitations one clear owner.

## Alternatives Considered
Tenant-contained duplicate credentials were rejected as the default because they create multiple passwords and make legitimate multi-gym participation difficult. Keeping the global `users.role` field as the authorization source was rejected because one account cannot safely have different authority in different organizations. Putting organization tables inside Identity was rejected because commercial tenant lifecycle is broader than authentication.

## Consequences
Existing role checks require a staged migration to membership-aware authorization. Tenant profiles and display identity eventually move behind membership-scoped APIs. The legacy global role remains transitional only and must not become a fallback once tenant enforcement is enabled.

## Implementation Notes
To be completed after implementation.
