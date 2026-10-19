# ADR-152: AI usage metering per call, operation and gym
Date: 2026-10-17
Status: Accepted

## Context
The workout assistant (ADR-105) reads a coach's free-text workout with several
Gemini calls: the structure agent, the proofreader (in parallel), the parser
with up to two tool rounds, and up to two repair passes, each of which may
itself take tool rounds. Workout icons (ADR-136) add one more call per
published workout. We had no way to say what one analysis costs, how much that
varies between workouts and runs, or what a gym's usage amounts to over a
month, which we need for pricing the assistant and for reporting to gyms. The
planned per-gym opt-in with the gym's own key
(`docs/plans/wod-assistant-opt-in-and-mandatory-journaling.md`) needs the same
numbers.

Every Gemini `generateContent` response carries `usageMetadata` with exact
token counts (`promptTokenCount`, `cachedContentTokenCount`,
`candidatesTokenCount`, `thoughtsTokenCount`, `toolUsePromptTokenCount`).

## Decision
1. **Measure at the source, per billed call.** Each Gemini adapter reads
   `usageMetadata` from every HTTP 200 response (including answers that later
   prove unusable, which are billed too) and emits one
   `[:milos, :ai, :generation]` telemetry event through
   `MilosTraining.AiUsage.report_generation/3`. Tokens are normalized by
   `TokenUsage` so each is billed once: input (prompt + tool-use prompt −
   cached), cached input, output, thinking (billed at the output rate).
2. **Operations group calls.** A user action (one analysis, one icon
   suggestion) gets an `operation_id`; callers pass it with `feature`,
   `organization_id` and `user_id` as `options.metering`, and adapters forward
   only those keys. `AnalyzeFreeText` returns `operation_id` with its result.
3. **Persist per gym.** `RecordAiUsage`, attached at application start, stores
   every event that names a gym in `ai_usage_records` (tenant RLS, append-only,
   purged with the tenant, ADR-117). Untenanted calls (local measurements) are
   not stored. Recording never fails the user's action.
4. **Price at the time of the call.** `PriceList` holds dated list prices in
   nano-USD per token (USD per 1M tokens × 1000), so costs are exact integers.
   Each row stores the cost at the rate in force that day; a model missing from
   the list is stored with no cost and counted as unpriced, never as free.
5. **Report.** `AiUsage.operation_usage/2` lists one operation's calls and
   totals; `AiUsage.usage_summary/2` aggregates a period per feature and model
   (operations, calls, tokens, cost, mean cost per operation).
6. **Measure repeatably.** `mix milos.ai.measure_free_text` runs the real
   analysis N times per sample workout (`bench/free_text_workouts.txt` by
   default) and prints every run plus mean, sample sd and standard error of the
   mean for cost, tokens, calls and wall time; `--out` writes every run and
   call as JSON, `--priced-at` re-prices at another day's list price.

## Rationale
Usage reports from the provider console are per key and per day: they cannot
separate features, gyms or single analyses, and comparing before/after
snapshots is noisy. The response's own usage report is exact and free. A
telemetry event keeps adapters ignorant of storage, lets the measurement task
observe the same numbers without a database, and works unchanged for any
future provider or model. Storing the cost at call time keeps reports
reproducible across price changes (Gemini 3.8 Flash doubles on 2027-01-01).

## Alternatives Considered
- **Before/after comparison in Google AI Studio.** Coarse, per key, delayed,
  and mixes in every other call made with the key. Kept only as a cross-check.
- **Returning usage through the analyzer port.** Would change every port
  callback and fake for a cross-cutting concern, and still miss the
  proofreader task's calls when it is cancelled.
- **Pricing at report time.** Simpler table, but historical reports would
  silently change with every price change.

## Consequences
- One insert per billed call, in the calling process (a few per analysis).
- `PriceList` must be updated when Google changes prices: add a dated entry,
  never edit a past one.
- `WorkoutIconSuggester.suggest/2` now takes the metering context.
- A platform/vendor API or admin screen over `usage_summary/2` is the next
  step when gyms are billed for the assistant.

## Implementation Notes
- Thinking tokens dominate parser cost at `parser_thinking_level: medium`; the
  measurement task reports them separately so thinking levels can be compared.
- Gemini's implicit context caching makes repeated runs of the same long
  system prompt cheaper; cached tokens are reported separately.
