# ADR-052: Structured PR Results and Supporting Metrics
Date: 2026-07-17
Status: Accepted

## Context

Pantheon PRs currently store a name, one score, one unit, comparison direction,
and achieved date. That keeps the board visually clear, but it cannot capture
the context that makes a result meaningful: a weight result may need reps and
sets, while a repetitions result may need load or elapsed time. Free-text-only
notes would preserve anecdotes but could not support future coaching or
analytics, and a note on the PR record alone would overwrite the context of a
previous result.

## Decision

Keep each PR's primary score and canonical unit as the comparable headline
value. Add an optional, controlled `supporting_metrics` map and optional
private `notes` to both the current PR record and each historical PR result.

The accepted supporting metrics are typed and finite: `reps`, `sets`,
`load_kg`, `duration_seconds`, `distance_m`, `calories`, `rounds`, and
`variation`. The UI presents meaningful options by primary unit through an
explicit Add details control; it never accepts arbitrary metric names.

When an updated score replaces the current result, its prior score, date,
supporting metrics, and notes are copied to PR history together. Cards keep
the primary score prominent and do not expose private notes.

## Rationale

The typed map gives users a quick, familiar form while retaining a stable
canonical vocabulary for analytics and coach-facing read models. Keeping the
primary unit constrained preserves score comparison and avoids unit strings
that downstream code cannot interpret.

Storing result context with historical values preserves auditability. It also
allows a later PR detail surface to distinguish a 60 kg five-rep result from a
different result without making every card dense.

## Alternatives Considered

Free-text notes only were rejected because they are not queryable and would
need manual interpretation for analytics.

Separate columns for every optional metric were rejected because the form
should grow without repeated schema migrations while still using a validated
finite metric vocabulary.

An unrestricted key/value metadata editor was rejected because it would create
inconsistent labels and units that defeat canonical analytics.

## Consequences

The current PR record remains a concise benchmark projection, while historical
rows become complete prior-result snapshots. New analytics can aggregate only
known metric keys; unknown keys are rejected at the domain boundary.

Changing the primary score archives the previous result. Editing only the
current result's contextual details corrects that result in place.

## Implementation Notes

- Added `supporting_metrics` JSON maps and private notes to both
  `user_pr_records` and `user_pr_history`. Existing rows receive an empty map
  by default.
- Added a pure Pantheon domain validator that normalizes accepted metrics and
  rejects unknown, negative, malformed, or blank values before persistence.
- PR updates archive the previous score with its date, metrics, and note when
  the primary score changes. Partial API updates that do not supply metrics
  retain the stored metrics.
- The form retains the primary-unit dropdown and provides a unit-aware Add
  detail selector for reps, sets, load, time, distance, calories, rounds, and
  variation. Notes do not appear on Pantheon cards; they appear in PR history.
- The focused ExUnit test could not start because the local PostgreSQL test
  database was unavailable at `localhost:5432`. The pure validator was checked
  directly with `mix run --no-start`; compile, architecture, TypeScript, lint,
  and OpenAPI generation passed.
