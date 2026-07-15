# ADR-027: Coaching Athlete Drill-Down Contract
Date: 2026-06-13
Status: Accepted

## Context
Phase 8 requires the admin dashboard to drill down from coaching summaries into
a single athlete profile that supports adherence review, performance
interpretation, coaching context, and follow-up decisions.

The existing backend already has source reads for athletes, assigned workouts,
workout executions, and coaching notes, plus a write path for admin athlete
notes. It does not yet expose one backend-supported profile that distinguishes
recent activity, assignment state, completion history, score trends, notes,
attention cues, and available coaching actions.

## Decision
Expose a dedicated admin coaching drill-down read for a single athlete. The
application service composes public Identity, Workouts, Execution, and Coaching
APIs, then delegates interpretation to a pure Coaching domain composer.

The existing admin note write endpoint remains the primary action endpoint for
this surface. The drill-down response advertises action readiness for
note-writing and review workflows without creating new persistence.

## Rationale
The drill-down spans multiple bounded contexts, so the composition belongs in an
application service. Keeping status and attention interpretation in a pure
Coaching domain module makes the contract testable without database fixtures and
prevents frontend-specific inference from becoming product logic.

Using a dedicated read endpoint keeps the existing note write API stable and
gives the unified `/admin` coaching tab a single profile contract.

## Alternatives Considered
Returning raw execution, assignment, and note lists separately was rejected
because it would force the frontend to infer coaching meaning and duplicate
status rules.

Putting the read into the Execution or Workouts contexts was rejected because
neither owns the coaching decision surface.

Persisting a separate coaching drill-down projection was rejected because the
surface can currently be derived from existing source facts.

## Consequences
The admin coaching drill-down is an interpreted read model. Source facts remain
owned by their bounded contexts.

Future frontend work should use this endpoint for `AthleteDrillDown` and keep
the existing note endpoint for note creation.

If additional coaching actions are added later, they must define eligibility and
blocked-action reasons in the same contract.

## Implementation Notes
Implemented as `GET /api/admin/athletes/:id/drill-down`, returning identity,
recent activity, assigned workout status, execution history, score trends,
notes context, attention cues, and available actions.

The read is composed in `GetCoachingAthleteDrillDown` from public Identity,
Workouts, Execution, and Coaching APIs. Interpretation remains in the pure
`Coaching.Domain.AthleteDrillDown` module.

The implementation reuses the existing `POST /api/admin/athletes/:id/notes`
action for note creation. No new storage, jobs, or cross-context writes were
added for Phase 2.

No backend follow-up work was deferred from this phase.
