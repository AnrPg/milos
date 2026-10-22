# ADR-180: Workouts written in text sections, the WOD-assistant switch and section scoring
Date: 2026-10-22
Status: Accepted

## Context
The redesign planned (PR #4) that a gym or a coach can work without the WOD
assistant: the WOD is then not parsed into exercises but written as text,
in sections, each with its own timer. Only the plan was merged; there was no
setting, no switch in the editor and no sectioned authoring. Coaches also
asked to say, per section, what it is scored by (rounds, reps, time, load…),
so that results of such workouts still feed progress and analytics.

## Decision
1. **Gym switch.** `organization_settings.settings["workouts"]["wod_assistant_enabled"]`
   (default on, `WorkoutSettingsPolicy`), shown in Settings → AI assistant.
   The server enforces it: the analysis returns 403 `assistant_disabled`,
   icon suggestions skip the model. `GET /workouts/authoring-settings` tells
   the editor.
2. **Per-workout switch** in the editor header. Off (or gym off) opens the
   sectioned editor; switching keeps the text (one free text becomes section
   1; sections become one text with a heading per titled section).
3. **Authoring mode `sectioned_text`.** Sections are ordinary `workout_sections`
   rows with `free_text_body`, `free_text_document` and `timer_preset`
   (`TimerPresets` shape, stopwatch allowed, required per section) and
   `section_metadata.untitled`. Publishing (`SectionedText.prepare_publish`)
   validates them (422 `invalid_text_sections` with per-section codes) and
   composes the workout's own `free_text_body` and `free_text_document`, so
   every existing free-text display works unchanged.
4. **Execution.** `Execution.build_timer_sequence/1` builds a sectioned workout's
   segments from each section's preset (`TimerPresets.build_sections`); the
   athlete runs one section at a time and starts each one. Section clocks may
   be restarted, so the never-decreasing elapsed-time check is skipped for
   text-section segments.
5. **Section scoring.** A section may carry `score_config.metrics`
   (`SectionScoring`: up to 6, each a coach label plus a kind among rounds,
   reps, time (seconds), load (kg), calories, distance (m) or custom number;
   keyed by the label's slug). The editor field offers fuzzy live suggestions
   from that list and «+» for the coach's own name. After the workout the
   finish screen asks one named field per metric; `text_section_scores`
   (`section_id`, `metric_key`, `value`) are checked against the workout
   (`TextSectionScores`) and stored as ordinary `section_scores` with
   `section_key = "<section id>:<metric key>"` and
   `section_name = "<section> · <metric>"`. Progress history, the coach's
   drill-down, training history and the journal therefore show one series per
   metric; the gym's WOD-of-the-day leaderboard ranks by the first metric
   (`ScoreRanking` matches `section_key`).

## Rationale
Reusing sections and section scores keeps one data model: no parallel table,
no special cases in analytics. Composing the workout text at publish keeps
every reader untouched. Numbers only (time in seconds) keep results
comparable over time.

## Alternatives Considered
* A separate `text_sections` JSON on the workout: simpler writes, but every
  timer, score and analytics reader would need a second path.
* Free-form string results: easy to type, impossible to chart or rank.
* Making text sections `scoreable`: would route them through the structured
  snapshotter, which expects exercises and one score per section.

## Consequences
* `normalize_workout` now exposes `authoring_mode`, which execution uses.
* Manual training-log entries of a sectioned workout do not ask for the
  section metrics yet (follow-up).
* Migration `20261201110000_sectioned_text_workouts` adds the section columns
  and the new authoring mode to the check constraint (reversible).

## Implementation Notes
* Metric keys come from the label, so renaming a metric starts a new series.
* The editor checks the same publish rules locally before the round trip and
  maps server problems back onto the section cards.
