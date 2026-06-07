# Agent Instructions — Gym App

> **This file is the entry point for every agent working on this project.**
> Read it in full before taking any action. It tells you what the app is,
> where the authoritative specs live, and the non-negotiable rules you must
> follow on every task.

---

## What This App Is

A fully responsive web application for a gym owner who:
1. Runs **in-person group classes** (CrossFit, Strength, Gymnastics, Aerobics, Flexibility, Recovery)
2. Provides **personalized online workout programming** to remote athletes

The app has three user roles — **Admin** (gym owner/trainer), **Gym Member** (attends classes), and **Athlete** (receives bespoke programming) — and covers class scheduling + booking, workout execution with a step-synced timer, gamification (streaks, PRs, challenges, leaderboard), and an admin dashboard with financial and coaching analytics.

It is self-hosted on the owner's servers. All services are free/open-source. No ads, no dark patterns, no paywalls.

---

## STOP — Read These Documents Before Anything Else

You MUST read the following files **at the start of every session and before implementing any feature**:

| Document | Path | What it contains |
|---|---|---|
| **Design Doc** ⭐ | `docs/superpowers/specs/2026-06-05-gym-app-design.md` | Full PRD: user flows, data models, gamification, UI layouts, tech stack. Your single source of truth. |
| **Implementation Plan** | `docs/superpowers/plans/2026-06-05-gym-app-implementation.md` | 10-phase implementation plan with checklists, TDD steps, live tests, and commit guides. |
| **ADR Directory** | `docs/adr/` | All architecture decisions. Read existing ADRs before implementing anything structural. |
| **Technical Debt Ledger** | `docs/technical_debt.md` | Known deferred items. Check before and after each phase. |

> **If the design doc and this file conflict, the design doc wins.**
> If this file and the implementation plan conflict, raise the conflict — do not silently pick one.

---

## Architecture Constraints — These Are HARD Rules

Section §2 of the design doc (`2026-06-05-gym-app-design.md`) defines **non-negotiable architectural constraints**. They are reproduced here as a quick reference. Violating any of them requires **explicit human approval before proceeding**.

### Rule 1 — Hexagonal Architecture (4 Layers, No Skipping)

```
Interface     →  Phoenix Controllers, Channels, Plugs
Application   →  Use Cases / Application Services (MilosTraining.Application.*)
Domain        →  Pure Elixir business logic (no Ecto, no HTTP, no Redis)
Infrastructure →  Ecto Repos, MeilisearchClient, PushDispatcher, RedisCache
```

- Controllers call Application Services — NEVER Repo, NEVER Domain directly.
- Domain modules are pure functions — same input → same output, no side effects.
- Infrastructure modules implement `@behaviour` contracts defined by Application/Domain.

### Rule 2 — Phoenix Contexts as Bounded Contexts

Contexts: `Identity` · `Scheduling` · `Workouts` · `Execution` · `Gamification` · `Coaching` · `Notifications`

- No context may call another context's internal modules or schemas.
- Cross-context communication: Phoenix PubSub events OR context public API functions only.
- An Application Service orchestrates cross-context operations (never a controller).

### Rule 3 — Light CQRS Within Each Context

```
MilosTraining.<Context>.Commands.*   →  writes only (Ecto changesets)
MilosTraining.<Context>.Queries.*    →  reads only (never mutate state)
```

### Rule 4 — Application Services for Cross-Context Operations

`MilosTraining.Application.*` — one public `call/N` function, uses `with` for error propagation, no DB queries, no business logic (that lives in Domain).

### Rule 5 — Contract-First API

OpenAPI spec BEFORE the Phoenix controller. The generated TypeScript client (`apps/web/src/api/generated/`) is read-only — never manually edited.

### Rule 6 — No Direct Repo Outside Owning Context

```elixir
# ❌ FORBIDDEN
def show(conn, %{"id" => id}), do: Repo.get!(User, id)

# ✅ CORRECT
def show(conn, %{"id" => id}), do: Identity.find_by_id(id)
```

### Rule 7 — Required Infrastructure Patterns

| Pattern | Where |
|---|---|
| Phoenix PubSub for cross-context side effects | After any command that triggers side effects |
| Redis cache-aside (TTL 60s) | Landing Page API endpoint |
| Oban job chaining | Booking timeouts, push dispatch, analytics refresh |
| PostgreSQL Materialized Views | Leaderboard, coaching aggregates |
| Optimistic UI (Zustand rollback) | Execution Mode check-offs only |

### Forbidden Patterns (require human approval to use)

Business logic in controllers · Direct Repo calls outside owning context · Raw SQL mutations · Cross-context schema imports · Polling for real-time features (use Phoenix Channels) · Frontend editing generated API client · Full Event Sourcing · Microservices · GraphQL

---

## Mandatory Per-Phase Checklist

Every phase in the implementation plan must follow this checklist **in order**. Do not skip or reorder.

### At the START of every phase:

- [ ] **Read the design doc** — specifically the sections referenced in the phase checklist
- [ ] **Read relevant existing ADRs** in `docs/adr/` before making any structural decision
- [ ] **Write the ADR for this phase** (see format below) — do this BEFORE writing any implementation code

### During implementation:

- [ ] **TDD loop for every non-trivial function:**
  1. Write the failing test first
  2. Run it — confirm it fails for the right reason
  3. Write the minimal implementation to make it pass
  4. Run it — confirm it passes
  5. Refactor if needed
  6. Commit (test + implementation together)

- [ ] **Domain modules:** unit tests only — no DB, no mocks, no fixtures
- [ ] **Application Services:** integration tests with real DB (no mocks for DB)
- [ ] **Controllers:** `ConnCase` integration tests

### At the END of every phase:

- [ ] **LIVE TEST** — manually verify every user-facing flow described in the phase checklist. Do not skip. "Tests pass" ≠ "feature works". Run the app and use it.
- [ ] **Update the phase's ADR** — fill in `Implementation Notes` with:
  - Any emergent decisions taken during implementation
  - Any deviations from the plan and why
  - Any new constraints discovered (perf, security, data)
  - Any follow-up work explicitly deferred
- [ ] **Update `docs/technical_debt.md`** — append any deferred tasks with ID, phase, reason, priority
- [ ] **Commit & push** — follow the commit guide below

---

## Commit Guide

Every commit must be **atomic**, **semantic**, and **dependency-ordered**.

### Format

```
<type>(<scope>): <what> — <why>

[optional body: context that won't be in the code]
```

### Types

| Prefix | When |
|---|---|
| `feat` | New feature or behavior |
| `fix` | Bug fix |
| `test` | Adding or fixing tests |
| `chore` | Tooling, config, deps, CI |
| `docs` | Documentation, ADRs, specs |
| `refactor` | Restructuring without behavior change |
| `perf` | Performance improvement |

### Dependency-Preserving Order

Always commit in this order within a feature:

```
1. Migration
2. Ecto schema
3. Domain module (pure logic)
4. Commands (writes)
5. Queries (reads)
6. Context public API
7. Application Service
8. OpenAPI spec update
9. Phoenix Controller + Router
10. Generated TypeScript client (regenerate, commit as-is)
11. Frontend components / hooks / stores
12. Tests (if not already committed with each step above)
```

### Good vs Bad Messages

```bash
# ❌ Bad — describes WHAT, not WHY
git commit -m "add booking timeout job"

# ✅ Good — describes WHY and the mechanism
git commit -m "feat(scheduling): add BookingTimeoutJob — alert admin after X mins of no response

Oban job scheduled on booking creation. No-ops if booking already resolved.
Cancelled via Oban.cancel_job/1 on approval/rejection.
Prevents silent booking abandonment without polling."
```

---

## ADR Format

Save every ADR to `docs/adr/ADR-NNN-kebab-title.md`. Update `docs/adr/README.md` index after each new ADR.

```markdown
# ADR-NNN: [Title]
Date: YYYY-MM-DD
Status: Accepted | Superseded by ADR-XXX

## Context
[Why this decision was needed — the problem, constraint, or trade-off]

## Decision
[What was decided — one clear statement]

## Rationale
[Why this option over alternatives]

## Alternatives Considered
[What else was evaluated and why rejected]

## Consequences
[Trade-offs introduced, constraints on future work, follow-up tasks]

## Implementation Notes   ← fill in AFTER the phase is complete
[Emergent decisions, deviations from plan, new constraints discovered,
 deferred work]
```

---

## Technical Debt Ledger Format

Append to `docs/technical_debt.md`:

```markdown
| ID | Phase | Description | Reason deferred | Priority | Added |
|---|---|---|---|---|---|
| TD-NNN | Phase X | What was deferred | Why | High/Medium/Low | YYYY-MM-DD |
```

---

## Tech Stack Quick Reference

| Layer | Technology |
|---|---|
| Backend | Elixir / Phoenix 1.7+ |
| Auth | Guardian (JWT) + Argon2 |
| Real-time | Phoenix Channels (never polling) |
| Background Jobs | Oban |
| ORM | Ecto (changesets for all writes — no raw SQL mutations) |
| Search | Meilisearch (self-hosted) |
| Push Notifications | Web Push Elixir + Oban workers |
| API Spec | OpenAPI (open_api_spex) |
| Cache | Redis 7+ (Redix) |
| Frontend | Next.js 15 (App Router) + TypeScript |
| Styling | Tailwind CSS + shadcn/ui |
| Client State | Zustand |
| Server State | TanStack Query |
| Charts | Recharts |
| Calendar | react-big-calendar |
| Database | PostgreSQL 16 |
| Deployment | Docker Compose + Caddy (auto TLS) |

---

## Project Structure

```
milos/
├── AGENTS.md                          ← you are here
├── apps/
│   ├── api/                           # Phoenix backend (MilosTraining)
│   │   └── lib/milos_training/
│   │       ├── identity/              # Bounded context
│   │       ├── scheduling/            # Bounded context
│   │       ├── workouts/              # Bounded context
│   │       ├── execution/             # Bounded context
│   │       ├── gamification/          # Bounded context
│   │       ├── coaching/              # Bounded context
│   │       ├── notifications/         # Bounded context
│   │       ├── application/           # Cross-context Application Services
│   │       └── infrastructure/        # Adapters (cache, search, workers)
│   └── web/                           # Next.js frontend
│       └── src/
│           ├── app/                   # App Router pages
│           ├── components/            # UI components
│           ├── stores/                # Zustand stores
│           ├── hooks/                 # Custom hooks
│           └── api/generated/         # Read-only OpenAPI-generated client
├── docs/
│   ├── adr/                           # Architecture Decision Records
│   ├── technical_debt.md              # Technical Debt Ledger
│   └── superpowers/
│       ├── specs/
│       │   └── 2026-06-05-gym-app-design.md   ← READ THIS
│       └── plans/
│           └── 2026-06-05-gym-app-implementation.md  ← FOLLOW THIS
├── docker-compose.yml
└── Caddyfile
```

---

## Key Open Items — Decide Before Starting Phase 2

> These must be resolved before the Phase 2 migration runs.
> They cannot be changed without a new migration after that.

1. **Scale level labels:** `Beginner / Intermediate / Advanced` vs `Scaled / Rx / Rx+`
   — Confirm with the human before writing the `exercise_variations` migration.

2. **App name / branding:** Milos Training — affects `mix.exs`, `package.json`, `manifest.json`.
   — Confirmed on 2026-06-05 for Phase 0 implementation.

---

## Questions and Blockers

If you encounter any of the following, **STOP and ask the human** before proceeding:

- A task seems to require violating an architectural constraint (§2 of design doc)
- The design doc and the implementation plan contradict each other
- A structural decision is not covered by an existing ADR
- A database migration change would be destructive (drop column, rename, change type)
- A feature requires a new external dependency not already in the plan
- You are about to push to a remote repository
