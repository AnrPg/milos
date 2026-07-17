import type { PRSupportingMetrics } from "@/api/gamification";
import type { UiTranslator } from "@/i18n/presentation";

const DETAIL_LABELS: Record<keyof PRSupportingMetrics, (translate: UiTranslator) => string> = {
  load_kg: (translate) => `${translate("semanticLoad")} (${translate("kg1389845")})`,
  reps: (translate) => translate("reps702045f"),
  sets: (translate) => translate("sets2ab262f"),
  duration_seconds: (translate) => translate("time6c82e6d"),
  distance_m: (translate) => translate("meters6ad427c"),
  calories: (translate) => translate("semanticKilocalories"),
  rounds: (translate) => translate("roundsceeac4a"),
  variation: (translate) => translate("variation15920a4"),
};

const DETAIL_ORDER: (keyof PRSupportingMetrics)[] = [
  "load_kg",
  "reps",
  "sets",
  "duration_seconds",
  "distance_m",
  "calories",
  "rounds",
  "variation",
];

export function formatPRCardDetails(metrics: PRSupportingMetrics, translate: UiTranslator): string {
  return DETAIL_ORDER.flatMap((key) => {
    const value = metrics[key];
    return value == null || value === "" ? [] : [`${DETAIL_LABELS[key](translate)}: ${value}`];
  }).join(" · ");
}
