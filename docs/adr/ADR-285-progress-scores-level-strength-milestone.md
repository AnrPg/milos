# ADR-285: XP level, strength gain and next milestone replace «Κίνητρο»
Date: 2026-10-30
Status: Accepted

## Context
Ημερολόγιο › Πρόοδος showed «Κίνητρο» (Motivation) and «Επιμονή» (Perseverance) with one shared
infobox that described neither. Motivation was the share of the last 10 weeks on the weekly goal,
which the Συνέπεια card already shows over 12 weeks («Χ από 12 εβδομάδες στον στόχο»). ANR asked to
replace it with something that adds gamification and satisfaction, and picked all three proposals
from the mockups (artifact «Βαθμοί και φίλτρα Προόδου», 2026-10-30).

## Decision
Motivation is removed from the API and the page. Three cards take its place, each with its own
explainer:

1. **«Επίπεδο XP»** (`Gamification.Domain.Level`). XP = 50 per workout, 100 per PR (found in a
   workout or beaten by hand: `total_prs + advancement_count`), 150 per week on the weekly goal,
   300 per finished challenge. Level `n` → `n + 1` takes `200 + 100 × (n − 1)` XP. XP is **worked out
   from the stats on every read and never stored**.
2. **«Βελτίωση δύναμης»** (`Pantheon.Domain.StrengthTrend`, query `GetStrengthTrend`). For each weight
   PR (unit kg), the estimated 1RM (Epley, ≤ 12 reps, same rule as the web's `pr-trend.ts`) at its
   best today is compared with its best before the last 56 days. The score is the mean relative
   gain over lifts that have both; lifts first logged inside the window count as `new_lifts`. Nil
   (no card) when nothing can be compared. Computed on read from the PR history.
3. **«Επόμενο ορόσημο»** (`AchievementRules.next_milestone/2`). From the workout, PR and day-streak
   badge ladders, the unearned badge with the largest share done (tie: fewest steps left).

All three ride the landing payload (`gamification.level`, `.strength`, `.next_milestone`), which
every relevant write already invalidates (completion projection, PR create/edit/update, 60 s TTL).

`user_stats` gains `weeks_on_goal` (refreshed by `StreakCalculator` on each completion projection,
user-relative weeks, ADR-229) and `challenges_completed` (incremented when the projection completes
a challenge; backfilled from `user_challenge_progress`). Migration `20270330000000`.

## Rationale
- Deriving XP keeps one source of truth: a voided workout or a corrected stat changes XP at once,
  and nothing can be awarded twice. A ledger (`xp_events`, proposed in the mockup) would need
  listeners on every source and compensation on every undo for no gain the user can see.
- Strength is read-time because PRs are logged by hand at any time and the window slides daily.
- The milestone reuses the badges people already earn; no new rules to explain.

## Alternatives Considered
- XP ledger table with one row per cause: rejected above.
- Strength from every logged set instead of PRs: richer, but sets are not reliably weighted across
  WOD formats yet; PRs are what the Personal Records section already trends.
- Keeping Motivation next to the new cards: it repeated Συνέπεια.

## Consequences
- Weeks on goal use the person's current goal for past weeks (as the streak does), so raising the
  goal can lower XP for old weeks. Accepted for one consistent definition across the page.
- `user_stats.motivation_score` is no longer written or read; the column stays until every running
  release stopped selecting it (TD-285: drop it in a later migration).
- `weeks_on_goal` of existing people is filled on their next completion; prod held no real data.

## Implementation Notes
- Names checked against the ontology: «Επίπεδο XP» (not bare «Επίπεδο», which is the scale level),
  «Βελτίωση δύναμης» (not «Δύναμη», a workout-type family).
- Point values and the level curve live only in `Domain.Level` and reach the explainer through the
  API (`level.points`), so the copy never drifts from what is counted.
