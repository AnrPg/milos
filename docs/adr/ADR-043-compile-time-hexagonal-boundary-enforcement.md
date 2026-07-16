# ADR-043: Compile-time hexagonal boundary enforcement
Date: 2026-07-15
Status: Accepted

## Context
The repository follows hexagonal naming and directory conventions, but those
conventions are not consistently enforced. Application services import Repo,
Ecto queries, infrastructure adapters, and Phoenix Endpoint modules; some
controllers invoke context internals or infrastructure directly; context store
wrappers compile against concrete adapters; controller contract definitions
import Ecto schemas; and domain functions read the system clock internally.
These dependencies make isolated testing harder and allow future changes to
silently reverse the intended dependency direction.

## Decision
Introduce executable architecture boundaries:

1. Define ports in Domain/Application-owned namespaces. Adapter selection is
   injected through application configuration without concrete adapter defaults
   in context/domain modules; environment configuration owns every default.
2. Controllers invoke one application service or public context API and never
   internal queries, schemas, Repo, or infrastructure. Cross-context work always
   lives in `MilosTraining.Application.*`.
3. Application and context modules publish transport-neutral events through
   ports. Phoenix Endpoint, Channels, cache, search, storage, and job adapters
   point inward and are selected at the composition root.
4. OpenAPI schemas use transport-owned enums/value objects or public domain
   metadata functions, never Ecto schema modules.
5. Time-dependent domain functions require an explicit date/time or a pure
   clock value. Application services obtain time through an injected Clock port.
6. Add a CI architecture test built on `mix xref graph` plus explicit forbidden
   dependency rules. Violations fail locally through `mix precommit` and in CI.
7. Update the design document's bounded-context catalog whenever an accepted ADR
   introduces a context. The catalog includes Identity, Scheduling, Workouts,
   Execution, Gamification, Coaching, Notifications, Finance, Analytics,
   Feedback, Wellbeing, Messaging, and Pantheon.

## Rationale
Compile-time and CI enforcement turns architecture from documentation into a
maintained invariant. Runtime-configured ports keep bounded contexts testable
without making them aware of adapters. Explicit clocks make domain results
reproducible and prevent date-boundary bugs. Transport-owned OpenAPI metadata
prevents controllers from compiling against persistence schemas.

## Alternatives Considered
- Continuing with naming conventions and review was rejected because the audit
  demonstrates repeated violations across mature features.
- Moving all orchestration into Phoenix contexts was rejected because contexts
  are bounded-context APIs, not a substitute for the application layer.
- A macro-heavy custom architecture framework was rejected in favor of xref,
  behaviours, and small tests that remain transparent to contributors.
- Globally mocking time was rejected because it hides dependencies and is unsafe
  under concurrent tests.

## Consequences
- Several application services and controllers require new ports/facades.
- Test configuration must explicitly select in-memory adapters.
- Domain APIs with implicit `Date.utc_today/0` or `DateTime.utc_now/0` defaults
  receive required clock arguments, causing intentional call-site changes.
- CI gains a fast architecture job and new violations cannot be merged.

## Implementation Notes
Implemented 2026-07-16.

- Added application-owned ports for avatar/document storage, landing cache,
  PR search, readiness, realtime publishing, signed tokens, and related
  composition-root adapter selection. Store wrappers now fetch configured
  adapters instead of compiling against infrastructure defaults.
- Removed direct Repo/Ecto/infrastructure dependencies from audited application
  services, including landing page retrieval, messaging orchestration, calendar
  token handling, PR search, storage, and finance document access.
- Refactored messaging HTTP and channel entry points to use application services
  and public bounded-context APIs for cross-context authorization/enrichment.
- Replaced controller OpenAPI enum coupling to workout Ecto schemas with a pure
  domain metadata module.
- Moved time-dependent domain calculations to explicit date/time inputs at the
  application boundary so domain functions remain deterministic.
- Added `mix milos.architecture`, which scans application/context/domain and
  controller layers for forbidden infrastructure, Repo/Ecto, web, and implicit
  clock dependencies. The task is part of backend `mix precommit` and CI.
- Updated the design bounded-context catalog to include Identity, Scheduling,
  Workouts, Execution, Gamification, Coaching, Notifications, Finance,
  Analytics, Feedback, Wellbeing, Messaging, and Pantheon.
- Verification after implementation: `mix compile --warnings-as-errors`, `mix
  milos.architecture`, and `mix credo --strict --format oneline` all pass with
  the new OTEL dependencies and architecture rules.
