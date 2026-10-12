# ADR-100: Structured-first Workouts and Workout Assistant Hardening
Date: 2026-10-12
Status: Accepted (amends ADR-078, ADR-096, ADR-098)

## Context
Free text is only a way for coaches to write workouts quickly. Athletes and
members must always see and run the structured workout. The assistant that
turns text into structure therefore has to be reliable: answers must follow
the schema and every format variation, and the in-line text corrections it
offers as Accept/Reject buttons must always be applicable.

## Decision
### Structured-first display and execution
- `WorkoutPreviewDetail` shows the structured sections for every workout;
  a free-text body is shown only when a free-text workout has no structure.
- Execution uses the real timer sequence. The manual free-text timer is a
  fallback only when a free-text workout has no runnable structure or
  `workout_metadata.timer_inference == "incomplete"` (a section timer the
  assistant could not infer was left unresolved at publish time). The rule
  lives in `usesManualTimer` and drives start and resume.

### Two agents, one contract
- The `WorkoutTextAnalyzer` port has two callbacks: `parse/2` (parser agent,
  optionally with `:repair` feedback) and `proofread/2` (proofreader agent).
  They run in parallel; the proofreader is best-effort and can never fail or
  crash the request.
- `WorkoutAssistant.Contract` (pure domain) checks the parser's raw answer
  strictly: top-level shape, unknown keys, enums, every format's required and
  allowed timer keys and value kinds, one prescription and one load per
  exercise, numeric ranges, issue paths, verbatim `find_text`, actionable
  warnings, and that a whole-field text fix matches the field fix.
- `AnalyzeFreeText` sends violations back to the parser (at most two repair
  rounds) and keeps the answer with the fewest violations. The response
  reports `quality` (repair attempts, remaining violations, corrections).
- `WorkoutAssistant.Proofreading` keeps only verbatim, non-overlapping
  corrections, attaches each to the canonical field that contains the words
  (so Accept fixes both text and data) or keeps it as a text-only fix on the
  pseudo path `"text"`, and drops corrections that duplicate a parser fix.
  Rejecting a proofreading correction keeps the coach's text and fields; a
  fix whose words are no longer in the text is reported instead of applied.

### Agent tools
`WorkoutAssistant.Tools` provides Gemini function-calling tools executed on
the server: `lookup_exercises` (canonical catalog with aliases, fuzzy
matching and supported prescriptions), `get_timer_format`, `convert_units`
and `validate_draft` (the Contract). Prompts are generated from the
canonical vocabulary and catalog (`GeminiPrompts`), so they cannot drift from
validation.

## Rationale
Validation is deterministic and lives in the domain; the model is only asked
to fix what the contract can name precisely. A separate proofreader prompt
focuses on wording without competing with schema extraction.

## Alternatives Considered
- Letting the parser self-validate through `validate_draft` on every run:
  accurate but added 20–30 s of tool round trips. The tool remains available;
  by default the server runs the same contract after the answer and repairs
  only when needed.
- Unlimited tool rounds: latency grew to 30–40 s. Tool budgets are 2 rounds
  for the parser and 1 for the proofreader; afterwards calling is switched off
  and the agent must answer.

## Consequences
Live runs on mixed English and Greek workouts (typos, lb, unit-less loads,
E2MOM, Tabata, 21-15-9) returned zero contract violations without repair in
10–18 s. Publishing sends `workout_metadata.timer_inference`; legacy free-text
workouts without sections keep the manual timer.

## Implementation Notes
Also resolved: tour completion is stored on the account
(`users.completed_tours`, `POST /api/me/tours/:audience/complete`) and the
dev seed creates its admin with an email plus a demo organization.
