# ADR-275: Workout types in families, offered per gym
Date: 2026-10-29
Status: Accepted

## Context
A WOD's «Τύπος προπόνησης» was one of six hard-coded kinds (crossfit, strength, gymnastics, aerobics, flexibility, recovery), shown as raw English keys in the text editors. ANR asked whether the list should come from the gym's settings, like class types, and for more kinds, martial arts and dance among them.

Class types (Τύποι τμημάτων) are a different thing: each box's own names for its timetable, with credits, level and audience. Workout types feed stats, badges, challenges, colours and the AI assistant, so they need one shared vocabulary.

## Decision
ANR chose option C of the mockup (2026-10-29): the workout type stays a platform-wide list, translated everywhere, and each gym chooses which kinds its editors offer.

- `Palee.Workouts.Domain.WorkoutType` (mirrored by `apps/web/src/lib/workout-types.ts`) lists 45 kinds in 9 families: functional, strength, gymnastics, endurance, mind_body, combat, dance, outdoor, recovery. Keys match the box profile's disciplines (`BoxProfilePolicy`) where both name the same training. `aerobics` and `flexibility` stay as the original kinds, so stored workouts never change.
- Stats-like readers use the family: mastery badges count a family (the six original badges keep their keys; combat, dance and outdoor get new ones), colours are one token per family (`--workout-combat`, `--workout-dance`, `--workout-outdoor` added), library icons are per family, and the Vault filter offers families (sending their kinds).
- `organization_settings.settings.workouts.workout_types`: the kinds the gym's editors offer, in catalogue order; null (the default) offers every kind, and choosing every kind stores null again so later kinds show up. At least one kind stays on. Settings › «Τύποι προπόνησης» edits it; `GET /admin/workouts/authoring-settings` returns the effective list.
- Every picker (`WorkoutTypeSelect`) groups kinds by family, shows translated names only, and keeps a workout's own kind listed when the gym hides it.

## Rationale
One vocabulary keeps stats, badges and challenges comparable across gyms and with members' imported history, while the per-gym choice keeps a CrossFit box's picker short.

## Alternatives Considered
- A: the WOD takes the gym's class types, each mapped to a family. One list, but timetable names (Kids, Open gym) are not kinds of training. Not chosen.
- B: a separate per-gym «Τύποι WOD» list mapped to families. Flexible, but a second list to maintain. Not chosen.

## Consequences
- Adding a kind: add it to both catalogue files and its `Ui.semanticWorkout*` label in every locale.
- The DB column stays a string: no migration.
