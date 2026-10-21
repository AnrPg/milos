import type { Insight, MyInsights } from "@/api/insights";

/**
 * Pure helpers of the Πρόοδος insights slot (ADR-166). The API sends a rule,
 * a variant and numbers; the copy is `Insights.rules.<rule>.<variant>` with
 * the values below. Anything unknown (a newer server, or the e2e catch-all
 * `{}`) is skipped rather than shown half-formatted.
 */

export const INSIGHT_STATES = ["insights", "all_hidden", "no_pattern", "collecting"] as const;
export type InsightState = (typeof INSIGHT_STATES)[number];

const VARIANTS: Record<string, readonly string[]> = {
  sleep_prs: ["more_after_goal", "all_after_goal"],
  sleep_effort: ["harder_after_short"],
  time_of_day: ["best_part", "only_part"],
  cravings: ["part_and_trigger", "part", "trigger"],
  hydration: ["on_goal", "training_more", "training_less"],
};

const PARTS = ["morning", "afternoon", "evening", "night"];
const TRIGGERS = ["stress", "fatigue", "boredom", "social", "hunger"];

export type InsightSlot = {
  state: InsightState;
  insights: Insight[];
  hiddenCount: number;
  dataWeeks: number;
  minWeeks: number;
  windowWeeks: number;
};

const count = (value: unknown, fallback = 0) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.floor(value) : fallback;

/** The slot from a response, tolerating a partial or empty answer. */
export function insightSlot(data: Partial<MyInsights> | null | undefined): InsightSlot {
  const insights = (Array.isArray(data?.insights) ? data.insights : []).filter(isKnownInsight);
  const raw = data?.state;
  let state: InsightState = (INSIGHT_STATES as readonly string[]).includes(String(raw)) ? (raw as InsightState) : "collecting";
  if (state === "insights" && insights.length === 0) state = count(data?.hidden_count) > 0 ? "all_hidden" : "collecting";
  return {
    state,
    insights: insights.slice(0, Math.max(1, count(data?.max_shown, 3))),
    hiddenCount: count(data?.hidden_count),
    dataWeeks: count(data?.data_weeks),
    minWeeks: count(data?.min_weeks, 4) || 4,
    windowWeeks: count(data?.window_weeks, 12) || 12,
  };
}

function isKnownInsight(insight: unknown): insight is Insight {
  if (!insight || typeof insight !== "object") return false;
  const { rule, variant, params } = insight as Partial<Insight>;
  if (typeof rule !== "string" || typeof variant !== "string" || !VARIANTS[rule]?.includes(variant)) return false;
  if (!params || typeof params !== "object") return false;
  return insightValues(insight as Insight) !== null;
}

type Values = Record<string, string | number>;

/**
 * The message key (under `Insights.rules`) and its values: numbers stay
 * numbers (the caller formats them for the locale), parts and causes are
 * ICU `select` keys. Null when a needed value is missing.
 */
export function insightValues(insight: Insight): { key: string; values: Values } | null {
  const p = insight.params ?? {};
  const key = `${insight.rule}.${insight.variant}`;
  const num = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? value : null);
  const part = PARTS.includes(String(p.part)) ? String(p.part) : null;
  const trigger = TRIGGERS.includes(String(p.trigger)) ? String(p.trigger) : null;
  const need = (values: Record<string, string | number | null>): Values | null =>
    Object.values(values).every((value) => value !== null) ? (values as Values) : null;

  let values: Values | null = null;
  switch (key) {
    case "sleep_prs.more_after_goal":
      values = need({ ratio: num(p.ratio), hours: num(p.hours) });
      break;
    case "sleep_prs.all_after_goal":
      values = need({ count: num(p.pr_days), hours: num(p.hours) });
      break;
    case "sleep_effort.harder_after_short":
      values = need({ delta: num(p.delta), hours: num(p.hours) });
      break;
    case "time_of_day.best_part":
      values = need({ ratio: num(p.ratio), part });
      break;
    case "time_of_day.only_part":
      values = need({ count: num(p.pr_days), part });
      break;
    case "cravings.part_and_trigger":
      values = need({ count: num(p.part_count), total: num(p.total), part, trigger });
      break;
    case "cravings.part":
      values = need({ count: num(p.part_count), total: num(p.total), part });
      break;
    case "cravings.trigger":
      values = need({ count: num(p.trigger_count), total: num(p.with_trigger), trigger });
      break;
    case "hydration.on_goal":
      values = need({ onGoal: num(p.on_goal_days), logged: num(p.logged_days) });
      break;
    case "hydration.training_more":
    case "hydration.training_less":
      values = need({ training: num(p.training_percent), rest: num(p.rest_percent) });
      break;
  }
  return values ? { key, values } : null;
}

/** The weeks of data behind the shown findings (the most of them). */
export function shownWeeks(insights: readonly Insight[]): number {
  return insights.reduce((most, insight) => Math.max(most, count(insight.weeks)), 0);
}
