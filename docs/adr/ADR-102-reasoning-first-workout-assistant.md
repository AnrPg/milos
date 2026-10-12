# ADR-102: Reasoning-first Workout Assistant
Date: 2026-10-12
Status: Accepted (amends ADR-096, ADR-100, ADR-101)

## Context
Coach free text does not follow a DSL. Coaches order things differently:
- parameters come before or after the movements;
- rest is written on its own line;
- time limits appear at the end.

They also use their own shorthand (RFT, KBS, 9/6, 3', b/w), mix languages, and
leave out what "everybody knows" (Tabata = 20/10 × 8, EMOM = 60 s). The
canonical JSON Schemas (ADR-101) describe the target, not the input. The
assistant must therefore *interpret* the text the way a coach would. The
earlier prompts framed it as a parser ("convert", "never invent"). The
proofreader also pushed coaches to rewrite their normal shorthand.

## Decision
- **Interpreter, not parser.** The prompts frame both agents as coaches
  reading another coach's workout.
  - The structure step also returns a one-sentence `intent` per block,
    including parameters written elsewhere in the text. The parser receives
    these intents with the outline.
  - The parser follows an explicit way of working: understand the whole
    workout → choose formats → compute derived values and apply conventions →
    keep information the schema cannot hold in notes → record assumptions →
    check against each format's schema.
- **Assumptions.**
  - The answer has an `assumptions` list (`{path, message}`) for
    interpretations a coach could disagree with: conventions, computed values,
    implied formats, choices within ranges or Rx/scaled pairs, the scope of
    "2 rounds", and ambiguous abbreviations.
  - Plain unit conversions and standard shorthand are excluded, which keeps the
    list at about 0–5 per workout.
  - Paths may name single timer keys (`sections.N.timer.KEY`).
  - The Contract checks that every assumption points at a real field.
  - `FreeTextAnalysis` turns assumptions into `code: "assumption"`,
    `severity: "info"` issues.
    - Assumptions about the same field (for example several timer keys)
      merge into one card.
    - **Keep** accepts the inferred value; **Reject** clears it, like any
      rejection. A real issue on the same field takes precedence.
- **Proofreader scope.** The proofreader accepts coach habits and flags only
  real mistakes:
  - misspellings;
  - genuinely unclear units;
  - impossible numbers;
  - shorthand that is not standard in gyms;
  - missing timer values;
  - real ambiguity.
- **Example library.**
  - `priv/workout_assistant/examples/*.json` holds curated coach text with
    its expected answer.
  - The examples are loaded at compile time by `WorkoutAssistantExamples` and
    rendered into both prompts: full answers for the parser, sections only
    for the structure step.
  - A test requires every example to pass the Contract, to normalize without
    blocking problems, and to keep its assumptions. A wrong example cannot
    teach the model wrong output.
  - Four starter examples cover:
    - a whiteboard with abbreviations;
    - strength supersets with an odd/even EMOM;
    - Greek text with the time limit after the movements;
    - terse text that needs conventions, plus a value nobody can infer.
  - Real gym samples are added the same way.
- **Reasoning budget.** The parser's thinking level is configured separately
  (`GEMINI_PARSER_THINKING_LEVEL`, default `medium`). The structure and
  proofreading agents stay at `GEMINI_THINKING_LEVEL` (`low`).
- **Robustness.** A tool failure is reported back to the model as an error
  instead of crashing the analysis. This was found live: `convert_units`
  crashed on whole-number results.

## Rationale
- The schema stays the single, verifiable target. Interpretation happens in
  the model, and every inference is visible and reversible for the coach.
- Few-shot examples are the most effective way to teach coach habits. Keeping
  them as validated data lets the library grow with real samples without
  code changes.

## Alternatives Considered
- **Deterministic pre-parsing of coach shorthand on the server.** Rejected:
  it is brittle across languages and styles, which is exactly what the model
  handles well.
- **Recording every inference, unit conversions included.** Tried live: 10+
  info cards per workout buried the real decisions.
- **Raising thinking for every agent.** Rejected: the structure and
  proofreading steps are classification tasks, and higher levels only add
  latency.

## Consequences
- Live results with the medium parser on three messy texts outside the
  examples (English, Greek/English, endurance):
  - 0 contract violations and no repairs;
  - total latency 12–21 s (low thinking: about 10–11 s);
  - 3–4 assumptions and 0 proofreading corrections per workout.
- Examples cost prompt tokens on every analysis (about 6k tokens for the
  parser prompt today), so the library should stay curated rather than
  exhaustive.

## Implementation Notes
- Example answers must use the same paths the model uses
  (`sections.N.timer.KEY`, `workout.estimated_duration_minutes`).
- The README in the examples folder explains the format and rules.
