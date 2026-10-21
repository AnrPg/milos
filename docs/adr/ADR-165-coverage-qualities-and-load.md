# ADR-165: Muscle coverage, the qualities radar and training load in Πρόοδος
Date: 2026-10-21
Status: Accepted

## Context
Vision §7.7 (analytics catalog) and Phase 3 milestone P3-M3 add three Πρόοδος
sections: muscle coverage (sets per group, push/pull and quad/ham balance),
a radar of the ten fitness qualities, and training load (session RPE,
acute:chronic) shown as an overload *indicator*. §8.6 and the plan's §6
checklist require that load is never a verdict or medical advice. P3-M2
(ADR-164) left open a coach view of a client's coverage and the link from
`Πρόοδος › Μυϊκή κάλυψη` into the atlas.

P3-M2 already provides the pure `Anatomy.Domain.CoverageWeighting` and
`Coverage`, `Application.AthleteTrainingVolume.load/2` (executions, training
logs and felt feedback across organizations) and `/journal/atlas` with
`atlasHref(node)`.

Facts found while exploring:
- Only training-log entries store perceived effort (`perceived_effort`) and
  duration; timed executions store elapsed time but no effort.
- Device workouts (Garmin) are not training-log entries, so they do not
  reach these sections today.
- The coach seam already exists: `{:coach, organization_id}` feed scopes on
  executions and training logs (ADR-139 §6, ADR-162 audiences) and row
  policies on `goal_feedback`.

## Decision
1. **One read, three sections.** `Application.TrainingDepth.build/4` loads the
   athlete's training once through `AthleteTrainingVolume` and builds:
   - coverage: `Anatomy.coverage/3` (unchanged ADR-164 weighting) summarised by
     the new pure `Anatomy.Domain.CoverageBalance`: up to three most-trained
     and three least-trained (level none/low, lowest first) of 14 major groups,
     plus push:pull and quad:ham;
   - qualities: the new pure `Anatomy.Domain.QualityProfile`: sets per quality
     from `ExerciseTargets` qualities, a 0..1 score relative to the top
     quality, felt counts, always all ten in canonical order;
   - load: the new pure `Analytics.Domain.TrainingLoad`: session load = RPE ×
     minutes; acute = last 7 days; chronic = weekly average of the last 28
     days; ratio = acute ÷ chronic; bands `below` (< 0.8), `steady` (≤ 1.3),
     `above` (≤ 1.5), `well_above`; eight calendar weeks for a chart.
2. **Balance counts exercise sets by primary muscles.** A set is push when
   the exercise's primary muscles include a pushing muscle (pectoralis major,
   triceps, anterior/lateral deltoid), pull for a pulling one (lats,
   rhomboids, middle/lower trapezius, biceps, brachialis, posterior deltoid,
   teres major), half of each when both. Quad:ham works the same way. A ratio
   is given only once both sides have sets and reach 4 together.
3. **Load only with enough history.** The ratio and band appear only when
   rated sessions fall in at least three of the four 7-day blocks of the
   28-day window. Sessions without RPE or duration are counted
   (`unrated_sessions`) and never estimated.
4. **`AthleteTrainingVolume` extended, not duplicated.** Performances now carry
   `source` (provider id, `device`, `freeform`, like `EntrySource`),
   `minutes` and `rpe`; `load/3` takes `since: nil` (everything) and options
   `:user_id` and `:scope` (`:owner` or `{:coach, organization_id}`).
5. **`GET /api/me/progress/depth?range=&sources=`** (`GetMyTrainingDepth`):
   account-level, the caller's own data, ungated like the account Πρόοδος.
   Ranges are the Πρόοδος ranges (`4w 12w 6m 1y all`, `all` from the first
   recorded session); `sources` narrows like the rest of the page.
6. **`GET /api/org/:slug/staff/clients/:user_id/progress-depth?range=`**
   (`GetClientTrainingDepth`, capability `view_client_training`): only a coach
   of the gym (coach role), only for an active member there, only their own
   client unless head coach (`AuthorizeClientAccess`, ADR-100). Data is read in
   the coach's tenant session through `{:coach, organization_id}`: only
   entries on a rung that reaches the coach and shared with this gym; felt
   feedback follows its entry by row security. Aggregates only, no entry
   text. Default range 4 weeks.
7. **Web.** `TrainingDepthCards` renders three fixed slots (Μυϊκή κάλυψη, then
   Ποιότητες and Φορτίο side by side on wide screens). Πρόοδος mounts them
   after the existing statistics under the page's own filter
   (`ProgressDepthSections`). The coach sees the same cards in the client
   profile's «Προπόνηση» tab (`CoachTrainingDepthPanel`, section
   `training_depth`), with 4 weeks / 3 months / 6 months chips.

## Decisions (product and UX, taken without a board per the owner's instruction)
- **One endpoint for the three sections**: one request and one read of the
  training history; the three cards can never disagree about the range.
- **Fixed slots after the existing statistics, in the mockup's order
  (coverage, qualities, load)**: no reordering of current cards (§8.5); P3-M4
  insights can follow load in the next slot.
- **Every slot always renders**, with loading, problem and «Δεν υπάρχουν
  προπονήσεις…» inside it; a `{}` answer reads as no data.
- **The page's own range and provider chips drive coverage and qualities**;
  the exercise filter does not narrow them (coverage of "workouts containing
  squats" is not meaningful). No extra chips.
- **Load is always "as of today"** (last 7/28 days, 8-week chart), stated in
  the chart label: a ratio of a past window is not actionable.
- **No 3D figure in Πρόοδος**: muscle names as chips with a level dot, each
  opening `atlasHref(group)`, and «Άτλαντας ›» in the card header. The atlas
  is one tap away; three.js on a long page would be weight and clutter.
- **Only 14 major groups named, three most and three least**: small and deep
  muscles stay in the atlas; six chips fit a phone.
- **Ratios shown as numbers only («1,4 : 1»), with no "balanced/imbalanced"
  label**: quad:ham norms differ by sport; a number plus «Ένδειξη…, όχι
  στόχος» informs without judging. Below the minimum: «Λίγα σετ ακόμα».
- **Radar is a shape relative to the athlete's own top quality**, not a score
  against a norm; note «Το σχήμα δείχνει πού πήγε η προπόνηση, όχι βαθμό.»
  Short axis labels; the full names in the summary line and a screen-reader
  list.
- **Felt qualities as one line («Ένιωσα»: …)**, not a second polygon: same
  wording as the journal's «Ένιωσα: …», less ink.
- **Load copy is neutral**: «Αυτή την εβδομάδα: 1,4× της συνηθισμένης», bands
  «Πιο ελαφριά / Κοντά στο συνηθισμένο / Πάνω από το συνηθισμένο / Αρκετά πάνω
  από το συνηθισμένο», warning tint at most, never red, never advice («σκέψου
  …» from the mockup dropped). Always «Φορτίο = RPE × λεπτά. Ένδειξη …, όχι
  ιατρική συμβουλή.»
- **Unrated sessions are said, never estimated**: «n προπονήσεις … δεν έχουν
  RPE ή διάρκεια και δεν μετράνε.» Inventing an RPE would make the indicator
  look precise when it is not.
- **Threshold "3 of 4 weeks" before a ratio**: a ratio over a one-week history
  is noise; the empty state says when it will appear.
- **Coach view in the profile's Προπόνηση tab, not a new screen**, and the
  panel says «Μόνο από καταχωρήσεις που ο πελάτης μοιράζεται…». No atlas links
  for the coach (the atlas is the member's screen).
- **No coach-read audit rows for aggregates**: the coach reads no entry; marking
  every counted entry as "read" would mislead the member's per-entry log.
  Only already-shared entries count, so nothing new is exposed.
- **Week counting for levels**: 4w = 28 days, 12w = 84, 6m = 182, 1y = 364,
  `all` = from the first session (rounded weeks, at least one), so a level
  means the same per week as in the atlas.

## Rationale
- Pure, constant-driven domain modules are reviewable and unit-tested; the
  coverage numbers come from the same ADR-164 policy as the atlas.
- Reusing the coach feed scope and row policies keeps one definition of "what
  a coach may see" (ladder + audiences); no new tables or migrations.
- Exercise-level balance avoids double counting a compound lift on both sides
  through secondary muscles.

## Alternatives Considered
- **Three endpoints**: three reads of the same history. Rejected.
- **Balance from muscle-set totals** (pectorals + triceps vs lats + biceps):
  double-counts synergists and swings with secondary weighting. Rejected.
- **EWMA acute:chronic**: smoother, but harder to explain in one line; the
  rolling 7/28 ratio is the common reading and is labelled an indicator.
- **Estimating RPE for timed workouts** (e.g. RPE 6): invents data. Rejected.
- **Recording coach reads per counted entry**: see Decisions. Rejected.
- **Nightly materialised read model**: unnecessary at current volumes; can sit
  behind `AthleteTrainingVolume` later.

## Consequences
- Timed executions contribute to coverage and qualities but not to load until
  executions store an effort; an optional RPE on the finish screen is the
  natural follow-up.
- Device workouts are not training-log entries and do not reach these sections.
- `all` reads every execution and up to 2 000 log entries per request.
- Coverage is UTC-day based, like the atlas.

## Implementation Notes
- Files: `anatomy/domain/{coverage_balance,quality_profile}.ex`,
  `analytics/domain/training_load.ex`, `application/{training_depth,
  get_my_training_depth,get_client_training_depth}.ex`,
  `TrainingDepthController`, `Schemas.TrainingDepth`; web
  `src/api/training-depth.ts`, `src/lib/progress/training-depth.ts`,
  `src/components/member-app/progress/{TrainingDepthCards,
  ProgressDepthSections,CoachTrainingDepthPanel}.tsx`, e2e
  `progress-depth.spec.ts`.
- `RouteCapabilities`: `{TrainingDepthController, :client} =>
  [:view_client_training]`.
- Ethics checklist (plan §6): «Training load shown as an overload indicator,
  never a verdict» is met by this milestone.
