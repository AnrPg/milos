# ADR-164: Anatomy atlas, coverage weighting and the gym's exercises per muscle
Date: 2026-10-21
Status: Accepted

## Context
Vision §7.6 and Phase 3 milestone P3-M2 ask for an anatomy atlas: three levels (region →
muscle group → head), each node showing what it does, the athlete's own sets over the last
four weeks with a coverage level, and exercises from the gym's library with videos, plus a
heat-map mode. It must be reachable from the WOD goals (P3-M1, ADR-163) and from
`Πρόοδος › Μυϊκή κάλυψη` (built in P3-M3, which will reuse the same coverage computation).

P3-M1 delivered the code-owned taxonomy (`Anatomy.Domain.MuscleTaxonomy`, TA2 mesh ids),
`ExerciseTargets` keyed by Quick Text catalog ids, the 3D figure (`AnatomyFigure`, three.js,
the Z-Anatomy glTF assets in `public/anatomy/v1/`, plan D2) and `goal_feedback`. What was
missing: a definition of "sets per muscle", a read model over the athlete's training across
every provider (ADR-162), a way to find exercises and videos per muscle, and the screen.

Facts found while exploring:
- Executions store no performed sets; they reference the workout done (`master_workout_id`,
  `scale_level_slug`). Training-log entries carry `performed_exercises` (`name`,
  `exercise_ref`, `sets`, …) and may also point to a workout.
- The gym has no per-exercise video field. Its videos are the on-demand library
  (`content_videos`, ADR-098: title, tags, https link, published/archived, package-gated by
  `watch_on_demand`).

## Decision
1. **Coverage weighting is a pure domain policy**, `Anatomy.Domain.CoverageWeighting`:
   - weights: primary = 1 set, secondary = ½ set, stabilizer = 0;
   - reach: a target reaches its own node, every node above it, and (for a group) its heads;
     a set counts **once per node** at the strongest weight with which the exercise reaches
     it (a deadlift is one set for «Thighs», not two);
   - levels by weighted sets **per week** with explicit constants: none (0), low (> 0),
     medium (≥ 3/week), high (≥ 8/week); ranges `1w`, `4w` (default), `12w`;
   - felt feedback reaches nodes by the same rule, each entry counting a node once.
   `Anatomy.Domain.Coverage.build/3` aggregates performances into per-node `sets`,
   `per_week`, `level`, `felt` and the three `top_exercises`; `NodeExercises.for_node/1`
   lists catalog exercises whose primary or secondary targets reach a node.
2. **Reusable application service** `Application.AthleteTrainingVolume.load(context, since)`
   reads, in the member's personal session (own rows in every organization):
   completed executions (exercises of the workout done, at the chosen scale, sets from the
   coach's prescription else 1), logged training-log entries (voided never; performed
   exercises with their sets, else the exercises of the linked workout), and the felt
   feedback on those same entries. Each exercise is resolved to its catalog id
   (`Workouts.resolve_catalog_exercise/2`, plural-tolerant). Workouts are read once each,
   in their own organization's system context, like `ListWorkoutExecutions`.
3. **`GET /api/me/atlas?range=1w|4w|12w`** (`GetMyAtlas`): account-level, the caller's own
   data, ungated like the account Πρόοδος. Returns range, weeks, from/to, taxonomy version,
   thresholds, sessions, recognised/unrecognised exercise counts, felt entries and
   **only the nodes with sets or felt entries** (regions, groups and heads, tree order), each
   with `top_exercises` carrying catalog labels. No coach variant (left to P3-M3).
4. **`GET /api/org/:slug/anatomy/nodes/:node_id/exercises`** (`ListAtlasNodeExercises`,
   any member of the gym): the catalog exercises that train the node with role, label and
   the gym's videos. A published on-demand video is attached to an exercise when one of its
   tags, or its whole title, names it (catalog id, label or alias). Videos follow the
   library's package gate; without it the exercises come without videos and
   `videos_included` is false. Unknown node → 404.
5. **Descriptions live in web i18n** (`Anatomy.about.<group>`, one sentence, 12 locales);
   heads reuse their group's, regions show their groups instead.
6. **Web screen `/journal/atlas`** (Ημερολόγιο › Πρόοδος, `?node=` deep link via
   `atlasHref()`): interactive figure (front and back), breadcrumb Σώμα › Region › Group ›
   Head, tap to drill (`onPick`), node panel, mode switch «Εξερεύνηση | Η κάλυψή μου», range
   chips. Heat roles `heat-low|medium|high` added to `AnatomyRole` with theme tokens
   `--anatomy-heat-*`.

## Decisions (product and UX, all taken without a board per the owner's instruction)
- **Home: `/journal/atlas`**, highlighted under the Πρόοδος tab — the sitemap (§6.2) puts
  Μυϊκή κάλυψη under Πρόοδος in Ημερολόγιο; a separate route keeps Πρόοδος uncluttered and
  gives P3-M3 one link target (`atlasHref(node)`).
- **One screen, two modes in a segmented control** (as in the mockup prototype) instead of
  two screens — fewer places to learn; heat is a lens, not a destination.
- **Three ranges only: 1 / 4 / 12 weeks, 4 default** — «this week», the vision's 4 weeks, a
  training block; more options would be clutter.
- **Levels per week, not raw totals** — the same colour means the same thing whatever the
  range.
- **Thresholds 3 and 8 weighted sets/week** — common volume landmarks; labelled «Ένδειξη…,
  όχι στόχος» under the legend (§8.6: indicators, never verdicts).
- **Secondary = ½, stabilizer = 0** — stabilizing is not volume; matches how coaches count
  hard sets and keeps WOD-heavy weeks from painting the whole body.
- **Unknown set count = 1** — a WOD line without sets is still one exposure; never
  inflated by rounds the app cannot know.
- **Heat map at group level, heads only inside the selected group** — a whole body of heads
  is noise; drilling reveals detail where it was asked for.
- **Only non-empty nodes in the API** — small payload; the client treats a missing node as
  none, which also tolerates the e2e `{}` stubs.
- **Exercises: first 5, then «Όλες (n)»; primary before assisting, ones with a video first**
  — the useful ones fit on a phone without scrolling the panel away.
- **Videos from the on-demand library by tag/title, behind its package gate** — the gym
  has no per-exercise video field; tagging an existing video `deadlift` is zero new admin UI
  and never leaks paid content.
- **Exercise names from the catalog labels** (not translated) — same names as the
  workouts and the Quick Text DSL members already read.
- **«Κυρίως από: …» (top 3 exercises) and the felt count in the node panel** — explains
  where the number comes from; felt only shown when > 0.
- **Unrecognised exercises mentioned once, on the body level** — honest without
  repeating it on every node.
- **Empty states**: «Δεν υπάρχουν προπονήσεις σε αυτό το διάστημα.» / «Κανένα σετ εδώ…»;
  without a selected gym the exercises say «Οι ασκήσεις φαίνονται όταν έχει επιλεγεί box.»
- **Entry from WOD goals**: «Άτλαντας ›» in the goals sheet opens the main muscle; tapping
  a muscle chip opens that muscle. The strip itself stays unchanged (stable card).
- **Phone layout**: figure capped at 48vh so the panel stays reachable; desktop shows
  figure and panel side by side.
- **URL keeps the node** (`router.replace`) so a link or reload lands on the same muscle
  without filling history with every tap.

## Rationale
- A pure, constant-driven policy is reviewable, unit-tested and shared by atlas and P3-M3
  coverage/balance, so the two can never disagree.
- Reading in the member's personal session reuses the ADR-162 RLS predicates; no new tables,
  migrations or policies.
- Deriving execution sets from the prescription is the only data available and is stable;
  a log entry's own sets win when the member wrote them.

## Alternatives Considered
- **Counting stabilizers at ¼ / secondary at 1**: inflates coverage for core and grip from
  every lift. Rejected.
- **Summing groups into regions**: double-counts compound lifts. Rejected for "once per node".
- **A per-exercise video column or table**: new admin UI and migration for something the
  on-demand library already holds. Deferred.
- **Coverage computed nightly into a table**: unnecessary at current volumes (one member,
  ≤ 12 weeks); can be added behind `AthleteTrainingVolume` later.
- **Atlas as a section inside Πρόοδος**: clutters a long page; P3-M3 links to it instead.

## Consequences
- Adding a catalog exercise without an `ExerciseTargets` entry already fails a test; such an
  exercise would count as unrecognised here.
- Coverage is UTC-day based (range ends today UTC).
- Gyms attach demo videos by tagging on-demand videos with the exercise name or id.

## Implementation Notes
- Files: `anatomy/domain/{coverage_weighting,coverage,node_exercises}.ex`,
  `application/{athlete_training_volume,get_my_atlas,list_atlas_node_exercises}.ex`,
  `AnatomyAtlasController`, `Schemas.AnatomyAtlas`; web `src/api/atlas.ts`,
  `src/lib/anatomy/atlas.ts`, `src/components/anatomy/atlas/AtlasScreen.tsx`,
  `src/app/journal/atlas/page.tsx`. `/anatomy/nodes` is a tenant-scoped client prefix.
- `ExerciseDescriptors.resolve_catalog_entry/2` (exposed as
  `Workouts.resolve_catalog_exercise/2`) resolves a ref or a name.
- The 3D figure only animates while on screen; the Playwright spec scrolls it into view
  before asserting the framing.
- Open: a coach view of a client's atlas (P3-M3 decides with coverage), and
  per-exercise video management if gyms ask for more than tagging.
