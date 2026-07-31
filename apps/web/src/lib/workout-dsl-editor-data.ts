export const DEFAULT_WORKOUT_DSL_SOURCE = `[workout]
dsl-version: 1
title: New Workout
type: strength

[section: untimed]
title: Main Work

[exercise: Back Squat]
sets: 5
reps: 5
load: 70 %1rm
rest-between-sets: 2 min
[/exercise]
[/section]
[/workout]`;

export const COMMON_WORKOUT_WORDS = [
  "activation", "alternating", "breathing", "bracing", "controlled", "cooldown",
  "coordination", "deload", "dynamic", "easy", "effort", "explosive", "flexibility",
  "heavy", "intensity", "interval", "mobility", "moderate", "pace", "power",
  "progression", "quality", "recovery", "repetitions", "rounds", "scaling",
  "stability", "strength", "technique", "tempo", "unbroken", "warm-up",
];

export const EXERCISE_NAMES = [
  "Air Squat", "Back Extension", "Back Squat", "Bench Press", "Box Jump", "Burpee",
  "Clean", "Deadlift", "Dumbbell Row", "Front Squat", "Glute Bridge", "Handstand Hold",
  "Hip Flexor Stretch", "Kettlebell Swing", "Lunge", "Muscle-up", "Overhead Press",
  "Pallof Press", "Plank", "Pull-up", "Push Press", "Push-up", "Ring Row", "Row",
  "Run", "Shoulder Press", "Snatch", "Split Squat", "Strict Press", "Thruster",
  "Toes-to-bar", "Wall Ball",
];

export const QUICK_TEXT_EDITOR_CLASS =
  "min-h-[32rem] px-5 py-4 font-mono text-sm leading-6 outline-none whitespace-pre-wrap";
