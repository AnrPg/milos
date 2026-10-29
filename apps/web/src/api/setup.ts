import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// ADR-255: setup recipes («Συνταγή στησίματος») and the settings catalog («Προχωρημένα»).
type Json<Op extends keyof operations> = operations[Op]["responses"] extends Record<
  200,
  { content: { "application/json": infer Body } }
>
  ? Body
  : never;

export type SettingsCatalog = Json<"PaleeWeb.AdminSetupController.settings">;
export type CatalogSetting = SettingsCatalog["settings"][number];
export type SetupRecipes = Json<"PaleeWeb.AdminSetupController.recipes">;
export type SetupRecipe = SetupRecipes["recipes"][number];
export type RecipePlan = Json<"PaleeWeb.AdminSetupController.preview">;
export type RecipeChange = RecipePlan["changes"][number];
export type AppliedRecipe = Json<"PaleeWeb.AdminSetupController.apply_recipe">;

export function fetchSettingsCatalog(token: string) {
  return apiRequest<SettingsCatalog>("/admin/setup/settings", { token });
}

export function fetchSetupRecipes(token: string) {
  return apiRequest<SetupRecipes>("/admin/setup/recipes", { token });
}

export function previewSetupRecipe(token: string, key: string) {
  return apiRequest<RecipePlan>(`/admin/setup/recipes/${encodeURIComponent(key)}/preview`, { token, method: "POST", body: {} });
}

/** How a recipe treats settings the owner already changed (product decision 2026-10-29). */
export type RecipeMode = "all" | "defaults_only";

/**
 * Owner only. `prices`: the owner's prices for the recipe's packages, by code, in cents.
 * `mode`: "all" changes every setting; "defaults_only" keeps the ones the owner changed.
 */
export function applySetupRecipe(token: string, key: string, prices: Record<string, number> = {}, mode: RecipeMode = "all") {
  return apiRequest<AppliedRecipe>(`/admin/setup/recipes/${encodeURIComponent(key)}/apply`, {
    token,
    method: "POST",
    body: { prices, mode },
  });
}
