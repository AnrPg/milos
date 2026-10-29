import type { AppliedRecipe, RecipeChange, RecipePlan, SetupRecipe, SetupRecipes } from "@/api/setup";

// Test data for the setup recipes screens (ADR-255, mockup s10 A).

export const crossfit = {
  key: "crossfit_box",
  version: 1,
  name: "CrossFit box",
  names: { en: "CrossFit box", el: "CrossFit box" },
  summary: "Classes with a WOD of the day",
  summaries: { en: "Classes with a WOD of the day", el: "Τμήματα με WOD ημέρας" },
  provider_kind: "gym",
  settings: [],
  class_types: ["CrossFit", "Open gym"],
  packages: [
    { code: "setup_unlimited", name: "Unlimited", package_type: "subscription", billing_period: "monthly", base_price_cents: 7500 },
    { code: "setup_trial", name: "Trial", package_type: "trial", billing_period: "none", base_price_cents: 1000 },
  ],
  role_grants: {},
  documents: [],
} as unknown as SetupRecipe;

export const coach = {
  ...crossfit,
  key: "independent_coach",
  name: "Independent coach",
  names: { en: "Independent coach", el: "Ανεξάρτητος coach" },
  summaries: { en: "Online programming, no classes", el: "Online προγραμματισμός" },
} as unknown as SetupRecipe;

export function recipesPayload(overrides: Partial<SetupRecipes> = {}): SetupRecipes {
  return { recipes: [crossfit, coach], applications: [], can_apply: true, currency: "EUR", ...overrides } as SetupRecipes;
}

const change = (area: RecipeChange["area"], key: string, to: unknown, name: string | null = null, advanced = false) =>
  ({ area, key, action: area === "setting" || area === "provider" ? "set" : "create", from: null, to, name, advanced, owner_changed: false }) as RecipeChange;

export const plan = {
  recipe: "crossfit_box",
  version: 1,
  name: "CrossFit box",
  changes: [
    change("package", "package.setup_unlimited", 7500, "Unlimited"),
    change("package", "package.setup_trial", 1000, "Trial"),
    change("class_type", "class_type.crossfit", "CrossFit", "CrossFit"),
    change("class_type", "class_type.open_gym", "Open gym", "Open gym"),
    change("setting", "scheduling.default_auto_approve", true),
    change("setting", "scheduling.default_booking_window_days", 7),
    change("setting", "scheduling.default_cancellation_cutoff_minutes", 120),
    change("setting", "gamification.streak_shields", 2, null, true),
  ],
  manual: [],
  unchanged: [],
  kept: [],
  change_count: 8,
} as unknown as RecipePlan;

/** The same plan where the owner already set 20 places per class (product decision 2026-10-29). */
export const ownedPlan = {
  ...plan,
  changes: [
    ...plan.changes,
    { area: "setting", key: "scheduling.default_capacity", action: "set", from: 20, to: 16, name: null, advanced: false, owner_changed: true },
  ],
  change_count: 9,
} as unknown as RecipePlan;

export const applied = {
  plan,
  application: {
    id: "app-1",
    recipe_key: "crossfit_box",
    recipe_version: 1,
    applied_by_id: null,
    applied_at: "2026-10-29T10:00:00Z",
    changes: plan.changes,
    manual: [],
    change_count: 8,
  },
} as unknown as AppliedRecipe;
