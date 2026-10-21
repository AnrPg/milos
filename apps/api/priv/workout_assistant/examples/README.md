# Workout assistant examples

Worked examples of real coach text and the canonical answer the assistant
should produce. They are injected into the structure and parser prompts
(`GeminiPrompts`) as few-shot examples, so the model learns how coaches
write — not just the schema.

Add one JSON file per example (files are read in name order):

```json
{
  "description": "What this example teaches (coach habit, ambiguity...)",
  "locale": "en",
  "text": "The coach's text exactly as typed",
  "answer": { "workout": {}, "sections": [], "issues": [], "missing_fields": [], "assumptions": [] }
}
```

Rules, enforced by `test/palee/infrastructure/workouts/workout_assistant_examples_test.exs`:

- `answer` must pass `WorkoutAssistant.Contract` (the per-format JSON
  Schemas) against `text` — `find_text` must be verbatim, paths must exist.
- Interpretations a coach could disagree with (conventions, computed values,
  ranges, Rx/scaled choices, implied formats) belong in `assumptions`; plain
  unit conversions and standard shorthand do not.
- Keep examples short and varied; each one costs prompt tokens on every
  analysis.

The app recompiles the prompts when a file here is added, changed or removed.
