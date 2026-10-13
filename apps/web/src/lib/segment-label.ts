import type { UiTranslator } from "@/i18n/presentation";

/** Localized message for each `label_key` the timer sequence builder emits. */
const LABEL_MESSAGES: Record<string, string> = {
  transition: "timerLabelTransition",
  rest: "timerLabelRest",
  kcal_target: "timerLabelKcalTarget",
  kcal_target_open: "timerLabelKcalTargetOpen",
  death_by: "timerLabelDeathBy",
  emom: "timerLabelEmom",
  round: "timerLabelRound",
  set: "timerLabelSet",
  minute: "timerLabelMinute",
  odd_minute: "timerLabelOddMinute",
  even_minute: "timerLabelEvenMinute",
  work: "timerLabelWork",
  rest_round: "timerLabelRestRound",
  cluster: "timerLabelCluster",
  effort: "timerLabelEffort",
  effort_zone: "timerLabelEffortZone",
  recover: "timerLabelRecover",
  recover_drop: "timerLabelRecoverDrop",
};

export const SEGMENT_LABEL_KEYS = Object.keys(LABEL_MESSAGES);

type Labelled = {
  label: string;
  label_key?: string | null;
  label_params?: Record<string, string | number> | null;
};

/**
 * The segment's label in the viewer's language. Unknown keys (a newer API)
 * and sequences without keys (an older API) fall back to the English label.
 */
export function segmentLabel(segment: Labelled, translate: UiTranslator): string {
  const message = segment.label_key ? LABEL_MESSAGES[segment.label_key] : undefined;
  if (!message) return segment.label;
  return translate(message, segment.label_params ?? {});
}
