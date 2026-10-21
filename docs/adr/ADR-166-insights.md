# ADR-166: Insights in Πρόοδος
Date: 2026-10-21
Status: Accepted

## Context
Vision §7.7 (analytics catalog) lists sleep ↔ performance, time of day,
cravings and hydration as insights, shown only after enough data
(«e.g. ≥4 weeks») and always as indicators, never medical advice (§8.6).
Phase 3 milestone P3-M4 asks for insight rules and a nightly job, a Πρόοδος
insights section, sufficiency empty states and ethics labels; plan D4 sets
the threshold (≥4 weeks plus a minimum sample per insight) and the label
«Ένδειξη, όχι ιατρική συμβουλή»; the plan's ADR sketch adds that sections
switched off in Ρυθμίσεις produce no insights. The owner asked for a single
fixed slot, at most a few insights at a time, each dismissible.

P3-M3 (ADR-165) already gives `AthleteTrainingVolume` (sessions across every
provider with minutes and RPE), the Πρόοδος depth slots and the training
load card. Wellness (ADR-159) gives `DaySummary` (sleep minutes and water
against the member's own goals) and cravings; Body settings (ADR-158) hold
the journal-section switches; Pantheon keeps a PR history with dates.

## Decision
1. **A new `Insights` context.** Pure domain: the `InsightRule` behaviour
   (`id`, `section`, `item`, `minimum`, `compute`), `Sufficiency` (the
   four-week gate, local date and part of day in the recorded zone) and
   `InsightCatalog` (the rules in a fixed order, which apply, what the slot
   shows). Store port/facade/Ecto adapter, application use cases, a
   controller and an Oban worker.
2. **Five rules over the last 12 weeks**, each on top of the four-week span:
   - `sleep_prs`: training days with the night before logged, split by the
     member's own sleep goal; a finding when PR days come ≥1.5× as often
     after reaching it (`more_after_goal`) or only then (`all_after_goal`).
     Minimum 5 training days each side, 3 PR days.
   - `sleep_effort`: rated sessions after a short night are ≥1 RPE point
     harder on average (`harder_after_short`). Minimum 5 sessions each side.
   - `time_of_day`: days with sessions in one part of the day only (05–12,
     12–17, 17–22, 22–05); the part with PR days ≥1.5× as often as the rest
     (`best_part`) or the only one with PRs (`only_part`). Minimum two parts
     with 6 days each, 4 PR days.
   - `cravings`: ≥50% of cravings in one part of the day and/or one cause in
     ≥40% of those with a cause (never «other»). Minimum 8 cravings (5 with
     a cause to name one).
   - `hydration`: days on the member's own water goal out of days logged,
     and training vs rest days when they differ by ≥20 points. Minimum 14
     logged days.
3. **Results are stored per person and rule** in `user_insights` (migration
   `20261119100000`): `status` `finding | no_finding | insufficient | off`,
   `value` (variant, params, weeks of data), `fingerprint` (rule, variant
   and the named part/cause, never numbers), `dismissed_fingerprint`.
   Owner-only RLS (ENABLE + FORCE), listed in `@ready_personal_tables`, no
   coach policy, deleted with the account.
4. **Nightly job** `NightlyInsightsJob` (02:40, `analytics` queue): the definer
   function `palee_insight_candidates(since, after, limit)` answers the ids
   of people with any session, wellness entry or craving in the window
   (keyset, ids only); each is computed in their own session; one failure is
   logged and never stops the run.
5. **`GET /api/me/insights`** reads the rows and computes first when they are
   missing, older than 24 h, or out of step with the current section
   switches. `POST /api/me/insights/:rule/dismiss` and
   `POST /api/me/insights/restore` answer the new slot.
6. **Inputs reuse, not duplicate.** Sessions come from
   `AthleteTrainingVolume.load/3` (extended with the recorded zone `tz`,
   as ADR-165 extended it with minutes and RPE); wellness days from
   `Wellness.summarize_days`; PR days from Pantheon's history. A section
   switched off is not even read.
7. **Web.** `InsightsCard` in the fixed slot after Φορτίο
   (`ProgressConsole`), `src/api/insights.ts`, `src/lib/progress/insights.ts`,
   copy under `Insights.*` in all 12 locales (ICU `select` for parts of day
   and causes).

## Decisions (product and UX, taken without a board per the owner's instruction)
- **One slot, after Φορτίο, always rendered**: the slot ADR-165 reserved;
  loading, problem and empty states stay inside it (§8.5).
- **At most three findings, in the rules' fixed order, never ranked by
  strength**: a stable screen; ranking would reshuffle the card nightly.
- **Dismiss with ×, next finding takes the place**: the owner's ask with the
  least chrome. A dismissed insight stays hidden until its finding changes
  (fingerprint without numbers), so 2.4× becoming 2.5× does not bring it
  back, but «evening» becoming «morning» does.
- **«Κρυμμένα: n · Επαναφορά» only when something is hidden**: an undo path
  without a settings screen; one quiet line.
- **No finding when the data shows nothing clear**: «Κανένα σαφές μοτίβο…»
  instead of a weak or reversed claim (e.g. more PRs after short sleep is
  never stated).
- **Sufficiency empty state with progress («Μέχρι τώρα: 2 από 4»)**, and
  «Χρειάζονται λίγες ακόμα καταγραφές…» once four weeks exist but samples
  are short: the member knows why the slot is empty and what helps.
- **One ethics label under the list, linked to every finding
  (`aria-describedby`)**, «Από n εβδομάδες δεδομένων · Ένδειξη, όχι ιατρική
  συμβουλή.»; also shown in every empty state. A badge per line would triple
  the ink for the same message.
- **Not narrowed by the page's range or provider chips**: correlations need
  the full 12-week window and every provider; the window is fixed and said
  in the empty state.
- **Neutral copy, only against the member's own goals**: «εκτός πλάνου»-style
  wording, no "should", no advice; perceived effort is said as «βαθμολογείς…
  πιο κουραστικές», never "you trained worse"; cravings say when and with
  what, never a judgement.
- **Sections switched off produce nothing and are cleared**: the rule is
  stored `off` with no value; the read hides it at once and recomputes so
  the old values are gone. Hidden wellness items (sleep, water) switch their
  rules off too.
- **Member only, no coach view**: insights draw on private sleep, water and
  cravings; showing them to a coach would bypass the visibility ladder.
- **Erasing wellness or cravings data deletes the insights**: nothing derived
  from erased data survives (recomputed on next read).
- **Recompute on read when stale**: a new member does not wait for the night;
  the job keeps reads cheap.
- **PR "performance" uses PR days**: PRs carry a date only, so a PR day
  counts for the training day; for time of day only days with sessions in a
  single part count, to avoid guessing which session set the PR.

## Rationale
- Pure, constant-driven rules are reviewable and unit-tested; thresholds sit
  next to the copy they justify.
- Storing one row per rule makes dismissal, sufficiency progress and the
  "nothing clear" state possible without recomputation on every read.
- Reusing `AthleteTrainingVolume` and `DaySummary` keeps one definition of a
  session, a night and "on goal" across Πρόοδος, Ευεξία and insights.

## Alternatives Considered
- **Compute on every read**: correct but the volume read is heavy; rejected
  in favour of nightly + stale fallback.
- **Rank findings by effect size**: reorders the card; rejected (§8.5).
- **Dismiss for N days**: findings would return unchanged; rejected.
- **Statistical tests (p-values)**: too opaque to explain in one line at
  these sample sizes; fixed minimum samples plus clear ratio thresholds and
  the indicator label instead.
- **A badge on each insight**: clutter; one linked label instead.

## Consequences
- Device sleep from Garmin counts (it is a wellness entry); device workouts
  still do not reach `AthleteTrainingVolume` (ADR-165).
- Timed executions have no RPE, so `sleep_effort` reads training-log
  sessions only.
- The nightly run reads every candidate's 12 weeks; at larger volumes the
  candidate query and `AthleteTrainingVolume` can move behind a read model.
- Ethics checklist (plan §6): «Insights labelled as indicators, never medical
  advice; none before enough data» is met by this milestone.

## Implementation Notes
- Files: `insights.ex`, `insights/{insight,insight_store}.ex`,
  `insights/ports/insight_store.ex`,
  `insights/domain/{insight_rule,sufficiency,insight_catalog}.ex`,
  `insights/domain/rules/{sleep_prs,sleep_effort,time_of_day,cravings_pattern,hydration}.ex`,
  `infrastructure/insights/ecto_insight_store.ex`,
  `application/{compute_insights,get_my_insights,nightly_insights}.ex`,
  `workers/nightly_insights_job.ex`, `InsightsController`,
  `Schemas.Insights`; web `src/api/insights.ts`,
  `src/lib/progress/insights.ts`,
  `src/components/member-app/progress/InsightsCard.tsx`, e2e
  `progress-insights.spec.ts`.
- Config: `:insight_store`, Oban cron `40 2 * * *`; the store facade is in
  `@tenant_scoped_stores`.
- `EraseMyWellness` now also deletes the member's insights.
