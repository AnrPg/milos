# ADR-300: Operation registry and agent-ready API conventions
Date: 2026-10-29
Status: Proposed (v4 plan, `docs/plans/v4-agent-first-novel-features.md` §3.2–3.3, V4-M0)

## Context
v4 adds 14 features and makes AI agents first-class users of Palee (ANR, 2026-10-29): an agent must
be able to discover what it may do, read what it needs and act through the same rules as a person.
Today each use case is exposed only as a hand-written REST controller action with an OpenApiSpex
schema (ADR-134) and a capability entry (ADR-099, `PaleeWeb.RouteCapabilities`). LLM tools are
written separately inside each AI adapter (e.g. the workout assistant, ADR-105/111). Adding MCP and
in-app agents this way would mean a third and fourth copy of every schema, and no single place
that knows an action's risk, data classes or whether it can be previewed.

## Decision
1. **One registry.** Every use case exposed to people or agents is an operation module implementing
   the behaviour `Palee.Operations.Operation` (`spec/0`, optional `preview/2`, `execute/2`, optional
   `next_actions/2`). The spec holds name, version, kind (query/command), agent-oriented summary and
   description, input/output JSON Schema 2020-12, examples, capability and scope (ADR-099), risk
   (`:read | :write_reversible | :write_irreversible | :outward | :money`), data classes
   (`:personal | :health | :financial | :user_generated`) and idempotency.
2. **Generated surfaces.** REST routes and OpenApiSpex schemas, MCP tools, LLM tool definitions
   (converted per provider in the adapter) and TypeScript types are generated from the spec. No
   surface restates a schema.
3. **Execution path.** `execute/2` calls only a context's public API or an application service
   (ADR-043). The registry runs policy (capabilities ∩ delegation, ADR-301) before `preview` or
   `execute`, records an audit row for agent principals, and is the only way agents reach contexts.
4. **Commands are previewable.** Every command implements `preview/2` (a dry run returning the
   intended change). Approvals (ADR-301) execute exactly a previewed input, guarded by its hash
   and the ETags it read.
5. **HTTP conventions for registry operations:** RFC 9457 problem details with stable `type` URIs,
   per-field `errors` and an optional `remedy`; `Idempotency-Key` on commands, stored in
   `idempotency_records`; `ETag`/`If-Match`; cursor pagination; `fields=` selection; UTC plus the
   gym's zone (ADR-179); integer minor units with ISO 4217; described enum values.
6. **Versioning.** Breaking changes create a new operation version; the old one is marked
   deprecated in the spec and removed only when unused.
7. **Gradual adoption.** Existing use cases join by adding an operation module that wraps the
   existing service. Controllers and schemas stay as they are. `mix palee.operations.coverage`
   reports how much of the API is registered.

## Rationale
A single declarative contract is what OpenAPI-first and MCP both assume, and it makes "agent-
friendly" a property checked by tests rather than a style. Preview plus risk metadata is the
minimum an approval flow needs. Plain behaviours keep the code transparent, as ADR-043 requires.

## Alternatives Considered
- **Hand-written MCP tools next to controllers:** duplicates schemas and lets policy drift.
- **GraphQL as the agent surface:** flexible reads, but no standard place for risk, preview or
  idempotency, and a second API style to secure.
- **A macro DSL for operations:** shorter modules, but hides control flow and fights xref-based
  architecture checks.

## Consequences
- New contract tests: valid schemas, examples pass, capability exists, risk declared, every command
  previewable, every surface generated from the same spec.
- `mix palee.architecture` gains a rule: agent code calls contexts only through the registry.
- V4-M0 registers 25 existing reads as the pilot.
