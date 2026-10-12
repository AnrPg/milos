import { ApiError } from "@/api/client";
import type { EffectiveEntitlement } from "@/api/my-finance";

/** Package capabilities that unlock client Phase C screens (ADR-098). */
export type ClientCapability =
  | "watch_on_demand"
  | "view_advanced_analytics"
  | "request_form_reviews"
  | "receive_nutrition_plan"
  | "book_pt_sessions"
  | "book_assessments";

export type ClientFeature = "videos" | "progress" | "coaching" | "appointments";

/** A feature is available when the package holds any of these capabilities. */
export const FEATURE_CAPABILITIES: Record<ClientFeature, ClientCapability[]> = {
  videos: ["watch_on_demand"],
  progress: ["view_advanced_analytics"],
  coaching: ["request_form_reviews", "receive_nutrition_plan"],
  appointments: ["book_pt_sessions", "book_assessments"],
};

export function entitlementCapabilities(
  entitlement: EffectiveEntitlement | null | undefined,
): Set<string> {
  return new Set(entitlement?.plan?.capabilities ?? []);
}

export function hasCapability(
  entitlement: EffectiveEntitlement | null | undefined,
  capability: ClientCapability,
): boolean {
  return entitlementCapabilities(entitlement).has(capability);
}

export function hasFeature(
  entitlement: EffectiveEntitlement | null | undefined,
  feature: ClientFeature,
): boolean {
  const capabilities = entitlementCapabilities(entitlement);
  return FEATURE_CAPABILITIES[feature].some((capability) => capabilities.has(capability));
}

/** Features to show in navigation, in display order. */
export function entitledFeatures(entitlement: EffectiveEntitlement | null | undefined): ClientFeature[] {
  return (Object.keys(FEATURE_CAPABILITIES) as ClientFeature[]).filter((feature) =>
    hasFeature(entitlement, feature),
  );
}

/** A 403 from a capability-gated endpoint means "not in your package". */
export function isNotEntitledError(error: unknown): boolean {
  return error instanceof ApiError && error.status === 403;
}

function numericTerm(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
}

/** The coach's promised reply time (`online_coaching.response_sla_hours`). */
export function responseSlaHours(entitlement: EffectiveEntitlement | null | undefined): number | null {
  return numericTerm(entitlement?.plan?.terms?.response_sla_hours);
}

/** The package's cancellation cutoff, when the package sets one. */
export function cancellationCutoffHours(
  entitlement: EffectiveEntitlement | null | undefined,
): number | null {
  return numericTerm(entitlement?.plan?.terms?.cancellation_cutoff_hours);
}

export type AllowanceRemaining = { remaining: number | "unlimited"; limit: number | "unlimited" };

export function allowanceRemaining(
  entitlement: EffectiveEntitlement | null | undefined,
  key: "form_reviews" | "pt_sessions" | "assessments",
): AllowanceRemaining | null {
  const usage = entitlement?.allowances?.[key];
  if (!usage) return null;
  return { remaining: usage.remaining, limit: usage.limit };
}
