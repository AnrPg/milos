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

export const QUICK_TEXT_EDITOR_CLASS =
  "min-h-[32rem] px-5 py-4 font-mono text-sm leading-6 outline-none whitespace-pre-wrap";

export function sanitizeWorkoutDslPaste(html: string) {
  if (typeof DOMParser === "undefined") return "";
  const document = new DOMParser().parseFromString(html, "text/html");
  document
    .querySelectorAll("script,style,iframe,object,embed,form,meta,link")
    .forEach((node) => node.remove());
  document.querySelectorAll("*").forEach((node) => {
    for (const attribute of [...node.attributes]) {
      const name = attribute.name.toLowerCase();
      const value = attribute.value.trim();
      if (name.startsWith("on") || name === "style") node.removeAttribute(attribute.name);
      if ((name === "href" || name === "src") && !/^(https?:|mailto:|\/|#)/i.test(value)) {
        node.removeAttribute(attribute.name);
      }
    }
  });
  return document.body.innerHTML;
}
