# ADR-101: Canonical Section Format Schemas and Structure-first Parsing
Date: 2026-10-12
Status: Accepted (amends ADR-096, ADR-100)

## Context
A workout is a sequence of sections. Each section has its own format, so one
workout can chain a warm-up, an EMOM, a Tabata, a rest and a 21-15-9. The
formats differ in more than their timer keys:
- **Timer:** EMOM needs `duration_seconds` and `interval_seconds`; Tabata needs
  `work_seconds`, `rest_seconds` and `rounds`; ladders need `start_reps`,
  `step_reps` and more.
- **Exercise structure:**
  - rotating EMOM exercises run in one minute slot;
  - ladder, pyramid and death-by exercises take their reps from the ladder;
  - Tabata stations take their duration from the work interval;
  - a rest block has no exercises.
- **Scoring:** each format allows different score types.

The assistant previously got only a list of timer keys per format
(`get_timer_format`), and the strict `Contract` checked only those keys.
Exercise rules and scoring were implicit, and the prompt guide was wrong for
`death_by`. The agent also read the text and the structure in one step.

## Decision
### One canonical, verifiable schema per section format
- `Workouts.Domain.WorkoutAssistant.FormatSchema` (pure domain) generates a
  JSON Schema for every one of the 19 section formats from
  `WorkoutDsl.Vocabulary`, the specs that `TimerConfig` and the timer engine
  already use. Each schema covers:
  - **timer:** required keys (`required` ∪ `dsl_required`), optional keys,
    types and minimums, and enums;
  - **exercises:**
    - `interval_assignment` is required for `complex_emom` (slot 1..N) and
      limited to `1|2` for `even_odd`;
    - it is forbidden elsewhere;
    - `reps` is forbidden on ladder, pyramid and death_by exercises;
    - `duration_seconds` is forbidden on tabata, custom_hiit, billat and hrr
      exercises;
    - `sets` is forbidden on cluster exercises;
    - a rest block holds no exercises;
  - **score:** limited to the format's score types.
- A forbidden key is written as `{"not": {}, "description": reason}`, so the
  violation explains why.
- Cross-field rules that JSON Schema cannot express are listed with each
  format and enforced by `FormatSchema.rule_violations/2`:
  - interval ≤ duration;
  - complex_emom slots run 1..N without gaps and fit in the number of
    intervals;
  - a descending ladder starts above its minimum;
  - an ascending ladder ends at or above its start;
  - a pyramid starts at or below its peak.
- `Workouts.Domain.JsonSchema` is a small, dependency-free validator for the
  draft 2020-12 subset these schemas use (`type`, `properties`, `required`,
  `additionalProperties`, `items`, `enum`, `const`, ranges, lengths, `oneOf`
  with discriminator-aware errors, `not`, and `$ref` into `$defs`).
- `Contract` now validates the workout and each section against these schemas
  and adds the cross-field rules. The agent tool, the prompts and the server
  check therefore share one definition. The timer may be an object
  (canonical) or the older `[{key, value}]` list.
- A test proves that a section valid against its schema has a timer that
  `TimerConfig.normalize/1` accepts, for every format.

### Agent function
- `get_section_schema(formats[])` returns, for each format: how it runs,
  required and optional timer keys, score types, rules, and the section's
  JSON Schema. Unknown formats are listed separately.
- It replaces `get_timer_format` in the parser's tool set.
  `get_timer_format` remains as a narrow view.

### Structure first
- A new port callback, `outline/2`, is a fast, tool-free structure agent. It
  splits the text into sections and infers each section's format, with
  verbatim evidence.
- The server verifies the outline (`FormatSchema.verify_outline/2`): aliases
  resolve to canonical names, unknown formats reject the outline, and evidence
  that is not verbatim is dropped.
- The parser then receives the verified outline plus the JSON Schemas and
  rules of exactly the formats it uses. It keeps `get_section_schema` in case
  it needs another format.
- If the outline fails or is invalid, the parser runs in one step as before.
  `quality.structure_inferred` reports which path ran.
- The proofreader still runs in parallel from the start.

### Canonical data and execution
- `FreeTextAnalysis` maps:
  - `score` → `scoreable: true` and `score_config: {type}`, only when the
    format allows that score;
  - `interval_assignment` onto the exercise.
- The publish payload already carries both fields.
- The timer engine fix: `TimerSequenceBuilder` now cycles complex_emom slots
  by the number of slots. Before, minute 4 of a 3-slot EMOM had no exercises.

## Rationale
- JSON Schema is a language the model already reads well. It is also
  machine-verifiable, so what we tell the agent and what we enforce cannot
  drift.
- Generating the schemas from `Vocabulary` keeps one source of truth with
  persistence and execution.
- Inferring the structure first is cheap (about 2 s, no tools) and lets
  step 2 work against the exact contract of the formats in use. That is more
  precise than a prompt covering all 19 formats.

## Alternatives Considered
- **An external JSON Schema library** (e.g. ex_json_schema): rejected. It adds
  a dependency for a small subset, and the errors were less specific for
  `oneOf` sections.
- **Gemini constrained decoding (`responseSchema`):** rejected again (see
  ADR-100). It produced degenerate output for deeply optional schemas, and it
  cannot express the cross-field rules.
- **Letting the agent call `get_section_schema` as its first step instead of a
  server-orchestrated outline:** rejected. It is less deterministic, the
  outline cannot be verified before parsing, and it costs the same round trip.

## Consequences
- Each analysis costs one extra Gemini call. Live runs: about 2–2.5 s for the
  outline and 10–13 s in total for multi-format workouts, with 0 contract
  violations and no repairs.
- A new format or timer key in `Vocabulary` automatically appears in the
  schemas, the tool, the prompts and the Contract. Format descriptions in
  `FormatSchema` must be updated by hand.
- Scores and interval slots now reach published free-text workouts.

## Implementation Notes
- The integration test `MultiFormatWorkoutTest` runs one answer through the
  whole path:
  - it chains untimed, complex_emom, tabata, rest and ladder_descending;
  - it goes Contract → normalize → draft → publish;
  - it checks the per-section timer sequence.
- The review panel shows each exercise's interval slot ("Interval 2", or
  "Odd/Even intervals").
- The parser prompt no longer reports case, plural or hyphen-only differences
  from the catalog as misspellings.
