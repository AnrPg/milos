import type { AppliedRecipe, RecipeChange, RecipePlan, SetupRecipe } from "@/api/setup";

// Mockup s10 option A: four-plus cards «αυτό είμαι εγώ», a preview of what
// will be set up with prices that can change, then «Εφαρμογή».

export const RECIPE_ICONS: Record<string, string> = {
  crossfit_box: "gym",
  functional_hyrox: "bolt",
  personal_training_studio: "user",
  yoga_pilates_studio: "lotus",
  martial_arts_school: "shield",
  open_gym: "door",
  independent_coach: "sparkle",
};

export type PreviewPackage = { code: string; name: string; cents: number; period: string };

/** A rule the preview names in words: a setting (or the provider kind) and its new value. */
export type PreviewRule = { key: string; value: unknown };

/** Settings the preview words as rules; the others are counted under «Προχωρημένα». */
export const WORDED_RULES = new Set([
  "provider.kind",
  "scheduling.default_auto_approve",
  "scheduling.default_booking_window_days",
  "scheduling.default_cancellation_cutoff_minutes",
  "scheduling.default_capacity",
  "gamification.leaderboard_enabled",
  "trials.enabled",
  "trials.seats_per_class",
]);

export type Preview = {
  packages: PreviewPackage[];
  classTypes: string[];
  rules: PreviewRule[];
  /** Other settings the recipe sets, all under «Προχωρημένα». */
  advanced: number;
};

const codeOf = (change: RecipeChange) => change.key.replace(/^package\./, "");

export function previewOf(plan: RecipePlan, recipe: SetupRecipe | undefined): Preview {
  const periods = new Map((recipe?.packages ?? []).map((pkg) => [pkg.code, pkg.billing_period]));
  const packages = plan.changes
    .filter((change) => change.area === "package")
    .map((change) => ({
      code: codeOf(change),
      name: change.name ?? codeOf(change),
      cents: typeof change.to === "number" ? change.to : 0,
      period: periods.get(codeOf(change)) ?? "",
    }));
  const classTypes = plan.changes
    .filter((change) => change.area === "class_type")
    .map((change) => change.name ?? String(change.to));
  const settings = plan.changes.filter((change) => change.area === "setting" || change.area === "provider");
  const rules = settings.filter((change) => WORDED_RULES.has(change.key)).map((change) => ({ key: change.key, value: change.to }));
  return { packages, classTypes, rules, advanced: settings.length - rules.length };
}

/** "75", "75,50" or "75.5" in major units → cents; null when it is not a price. */
export function parsePrice(text: string): number | null {
  const clean = text.trim().replace(/\s/g, "").replace(",", ".");
  if (!/^\d{1,6}(\.\d{1,2})?$/.test(clean)) return null;
  return Math.round(Number(clean) * 100);
}

export function formatPrice(cents: number) {
  const units = cents / 100;
  return Number.isInteger(units) ? String(units) : units.toFixed(2);
}

/**
 * The prices to send: only those the owner changed. `{ prices }` or
 * `{ invalid }` with the codes whose text is not a price.
 */
export function changedPrices(packages: PreviewPackage[], drafts: Record<string, string>) {
  const prices: Record<string, number> = {};
  const invalid: string[] = [];
  for (const pkg of packages) {
    const draft = drafts[pkg.code];
    if (draft === undefined) continue;
    const cents = parsePrice(draft);
    if (cents === null) invalid.push(pkg.code);
    else if (cents !== pkg.cents) prices[pkg.code] = cents;
  }
  return invalid.length ? { invalid } : { prices };
}

/** «N πακέτα συνδρομής · M τύποι τμημάτων · K κανόνες» after applying. */
export function appliedCounts(applied: AppliedRecipe) {
  const changes = applied.application.changes;
  return {
    packages: changes.filter((change) => change.area === "package").length,
    classTypes: changes.filter((change) => change.area === "class_type").length,
    rules: changes.filter((change) => change.area === "setting" || change.area === "provider").length,
  };
}
