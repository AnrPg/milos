# ADR-105: AI-assisted Free-text Workout Authoring
Date: 2026-10-12
Status: Accepted (amends ADR-078; amended by ADR-109)

## Context
Free text became the only way to create workouts. ADR-078 kept free-text
workouts deliberately unstructured, which left them without canonical data
(sections, exercises, loads, timers) and gave coaches no feedback on typos,
ambiguous numbers or missing information. Coaches asked for a free-text
editor that still produces the canonical schema, explains problems in plain
language and lets them accept or reject every proposed fix.

## Decision
Add an LLM-backed workout assistant behind a new `WorkoutTextAnalyzer` port in
the Workouts context, with a Google Gemini adapter, exposed as
`POST /api/org/:slug/admin/workouts/free-text/analyze`.

- The adapter returns an untrusted reading. The pure domain module
  `Workouts.Domain.FreeTextAnalysis` validates it against the canonical schema
  (workout types, difficulties, units, load modes, `TimerConfig`), drops what
  it cannot validate, reports deterministic issues (missing title/type,
  section and exercise names, invalid values, incomplete timers), keeps
  assistant issues only for known paths and text edits only when the replaced
  text exists verbatim, and computes missing-field suggestions.
- Every issue carries a suggested canonical value and/or a text edit. Accept
  writes the value and applies the edit in the editor; Reject nullifies the
  field. Rejected required fields (title, type, section and exercise names)
  block creation; rejected optional fields are simply omitted.
- Publishing a free-text workout now also sends the accepted canonical
  metadata and sections. The free text stays the display source of truth
  (ADR-078 rendering is unchanged); the sections are the structured record.
- The review state is stored in `draft_data.free_text_review`, so it resumes
  after reload.
- Structured and Quick Text creation are hidden behind
  `SHOW_AUTHORING_MODE_SWITCHER = false`; their code stays, and drafts authored
  with them still open in their original editor.

## Rationale
The port keeps the provider replaceable and testable (a fake analyzer drives
controller tests). Validating in the domain layer means a hallucinated or
malformed answer can never reach the database: the worst case is a missing
suggestion. Reusing the existing publish pipeline avoids a second persistence
path.

## Alternatives Considered
- Asking the model to emit Quick Text DSL and reusing the DSL parser: DSL
  diagnostics point at generated source, not at the coach's text, so they are
  not actionable for the coach.
- Gemini constrained decoding (`responseSchema`): it returned truncated,
  degenerate objects for this deeply optional schema; JSON mode with the
  schema in the instructions was accurate.
- Calling Gemini from the browser: would expose the API key.

## Consequences
- New runtime configuration: `GEMINI_API_KEY` (server-side only),
  `GEMINI_MODEL` (default `gemini-3.8-flash`), `GEMINI_THINKING_LEVEL`
  (default `low`). Without a key the endpoint answers 503 and the editor still
  publishes text-only workouts.
- Each check costs one LLM call; there is no per-tenant quota yet (TD-057).
- Free-text workouts may now have sections; execution still uses the manual
  free-text timer (TD-058).

## Implementation Notes
Live testing: the default reasoning level took ~45 s for a ten-line WOD;
`thinkingLevel: low` answered in ~8 s with the same findings. The Next.js dev
rewrite cut requests at 30 s, so `experimental.proxyTimeout` is 90 s in dev;
production routes `/api` straight to Phoenix through Caddy. Publishing runs a
fresh check when the text changed since the last one and stops once so the
coach can review new notes before anything is created.
