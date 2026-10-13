# ADR-115: Dialyzer Baseline Paid Down to Zero
Date: 2026-10-12
Status: Accepted

## Context
ADR-090 made Dialyzer release-blocking but carried forward 98 inherited
warnings through `.dialyzer_ignore.exs` (TD-043). Ignore entries match by file
and message, so any new warning with a matching message in those files was also
hidden, and some of the suppressed warnings marked real defects.

## Decision
Fix every baseline warning at its root and keep `.dialyzer_ignore.exs` empty.
New warnings must be fixed rather than ignored; an ignore entry now needs its
own justification in review.

## Rationale
The baseline clustered around a few root causes. Fixing those removed most of
the warnings at once, and they had been hiding at least one production crash.

## Alternatives Considered
- Keep the ignore file and fix opportunistically: rejected because it keeps the
  masking risk and the crash it was hiding.
- Lower Dialyzer flags: rejected; it would hide the same defect class.

## Consequences
- `mix precommit` runs Dialyzer with zero skips.
- `:decimal` is in `plt_add_apps`, since several stores call `Decimal` directly.

## Implementation Notes
Root causes, by warning count:
- **Missing `@type t` (50).** Ports referenced `Identity.Account.t/0`, the
  Messaging schemas and the Organizations schemas, none of which defined `t`.
  Each module now declares it.
- **`MinioStorage` (25, plus 3 downstream in readiness and the bucket
  reconciler).** `ExAws.request/2` was given a resolved `ExAws.Config` map
  where its spec takes keyword overrides, so Dialyzer treated every storage call
  as non-returning. Request paths now pass keyword overrides; presigning still
  gets the resolved map. `ExAws.Config.new/2` calls `Map.new/1` on either shape,
  so runtime behavior is unchanged. There is no MinIO in the test environment,
  so this was checked against the library source, not a live bucket.
- **Unknown `Decimal` functions (5).** A PLT gap; fixed by adding `:decimal`.
- **Real defect.** `GetScheduleCalendar` matched `:error` from
  `Date.from_iso8601/1`, which returns `{:error, reason}`, so a malformed
  `start_date` raised `CaseClauseError` (HTTP 500) instead of 400. Fixed, with a
  regression test.
- **Dead branches.** `ChallengeCriteria.target/1` and
  `increment_per_completion/1` always return positive integers, so
  `target <= 0` and `pts > 0` were unreachable. `CreatePR` always normalized
  metrics. `action/3` in both drill-downs had an unreachable `if`.
  `WebPushDispatcher` and `SubmitReview.target_label/1` had unreachable clauses.
  Controllers used `conn.body_params || params` fallbacks that could never fire.
- **Deviation.** Dialyzer called `MeController`'s atom-key `avatar_key` clause
  unreachable, but OpenApiSpex casting does produce atom-keyed `body_params`,
  and removing the clause broke two controller tests. It now uses
  `Map.fetch/2` for both key shapes, with a comment explaining why.
