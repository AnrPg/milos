import type { FinanceRecord } from "@/api/finance";

// ADR-096: the package catalog is served by the API. These helpers never
// duplicate presets or lock rules; they only apply what the catalog says.

export type QuotaPeriod = "calendar_week" | "calendar_month" | "subscription_period";
export type QuotaValue = { limit: number | "unlimited"; period: QuotaPeriod };
export type DurationValue = { amount: number; unit: "day" | "week" | "month" };
export type ClassTypeLimit = { id: string; limit: number; period: QuotaPeriod };
export type PackageFields = Record<string, unknown>;

export type CatalogField = {
  key: string;
  section: string;
  kind: string;
  phase: string;
  available: boolean;
  options?: Array<string | number>;
  min?: number;
  max?: number;
};

export type CatalogLock = { path: string; field: string; value: unknown; reason: string };

export type CatalogType = {
  key: string;
  available: boolean;
  enabled: boolean;
  billing_model: "recurring" | "one_off" | "with_base";
  billing_periods: string[];
  default_billing_period: string;
  preset: PackageFields;
  billing_period_overrides: Record<string, PackageFields>;
  locks: CatalogLock[];
};

export type PackageCatalog = {
  version: number;
  implemented_phases: string[];
  modules: Array<{ key: string; available: boolean; enabled: boolean }>;
  sections: string[];
  fields: CatalogField[];
  types: CatalogType[];
};

export type PackageDraft = {
  packageType: string;
  billingPeriod: string;
  name: string;
  description: string;
  price: string;
  tags: string[];
  fields: PackageFields;
};

export type DraftIssue = { field: string; message: string };

export const ONE_OFF_TYPES = new Set(["class_pack", "drop_in", "trial", "pt_pack"]);

export function equal(left: unknown, right: unknown): boolean {
  return JSON.stringify(normalize(left)) === JSON.stringify(normalize(right));
}

function normalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, child]) => [key, normalize(child)]),
    );
  }
  return value;
}

export function findType(catalog: PackageCatalog, key: string): CatalogType | undefined {
  return catalog.types.find((type) => type.key === key);
}

export function selectableTypes(catalog: PackageCatalog): CatalogType[] {
  return catalog.types.filter((type) => type.available && type.enabled);
}

export function moduleEnabled(catalog: PackageCatalog, key: string): boolean {
  return catalog.modules.some((module) => module.key === key && module.available && module.enabled);
}

export function presetFor(type: CatalogType, billingPeriod: string): PackageFields {
  return { ...type.preset, ...(type.billing_period_overrides[billingPeriod] ?? {}) };
}

export function fieldSpec(catalog: PackageCatalog, key: string): CatalogField | undefined {
  return catalog.fields.find((field) => field.key === key);
}

export function fieldLocks(type: CatalogType, fieldKey: string): CatalogLock[] {
  return type.locks.filter((lock) => lock.field === fieldKey);
}

/** The whole field is pinned by the type. */
export function isFieldLocked(type: CatalogType, fieldKey: string): boolean {
  return type.locks.some((lock) => lock.path === fieldKey);
}

/** One key of a map-valued field (for example `limit` of a quota) is pinned. */
export function isPartLocked(type: CatalogType, fieldKey: string, part: string): boolean {
  return isFieldLocked(type, fieldKey) || type.locks.some((lock) => lock.path === `${fieldKey}.${part}`);
}

export function applyLocks(type: CatalogType, fields: PackageFields): PackageFields {
  const next = { ...fields };
  for (const lock of type.locks) {
    if (lock.path === lock.field) {
      next[lock.field] = lock.value;
    } else {
      const part = lock.path.slice(lock.field.length + 1);
      next[lock.field] = { ...((next[lock.field] as Record<string, unknown>) ?? {}), [part]: lock.value };
    }
  }
  return next;
}

export function newDraft(catalog: PackageCatalog, typeKey: string): PackageDraft {
  const type = findType(catalog, typeKey);
  if (!type) throw new Error(`Unknown package type ${typeKey}`);
  return {
    packageType: type.key,
    billingPeriod: type.default_billing_period,
    name: "",
    description: "",
    price: type.key === "trial" ? "0" : "",
    tags: [],
    fields: applyLocks(type, presetFor(type, type.default_billing_period)),
  };
}

/** Switching type keeps the basics and restarts the contract from the new preset. */
export function switchType(catalog: PackageCatalog, draft: PackageDraft, typeKey: string): PackageDraft {
  const fresh = newDraft(catalog, typeKey);
  return { ...fresh, name: draft.name, description: draft.description, tags: draft.tags, price: draft.price || fresh.price };
}

/**
 * Changing the billing period re-applies period-dependent preset values only
 * where the administrator kept the previous suggestion.
 */
export function changeBillingPeriod(type: CatalogType, draft: PackageDraft, billingPeriod: string): PackageDraft {
  const previous = presetFor(type, draft.billingPeriod);
  const next = presetFor(type, billingPeriod);
  const fields = { ...draft.fields };
  for (const key of Object.keys(type.billing_period_overrides[billingPeriod] ?? {})) {
    if (equal(fields[key], previous[key])) fields[key] = next[key];
  }
  return { ...draft, billingPeriod, fields };
}

export function changedFields(catalog: PackageCatalog, draft: PackageDraft): string[] {
  const type = findType(catalog, draft.packageType);
  if (!type) return [];
  const preset = presetFor(type, draft.billingPeriod);
  return catalog.fields
    .filter((field) => field.available && !equal(draft.fields[field.key], preset[field.key]))
    .map((field) => field.key);
}

export function resetField(catalog: PackageCatalog, draft: PackageDraft, key: string): PackageDraft {
  const type = findType(catalog, draft.packageType);
  if (!type) return draft;
  return { ...draft, fields: { ...draft.fields, [key]: presetFor(type, draft.billingPeriod)[key] } };
}

export function resetAll(catalog: PackageCatalog, draft: PackageDraft): PackageDraft {
  const type = findType(catalog, draft.packageType);
  if (!type) return draft;
  return { ...draft, fields: applyLocks(type, presetFor(type, draft.billingPeriod)) };
}

export function priceCents(price: string): number | null {
  const normalized = price.trim().replace(",", ".");
  if (normalized === "") return null;
  const value = Number(normalized);
  return Number.isFinite(value) && value >= 0 ? Math.round(value * 100) : null;
}

export function anyServiceIncluded(fields: PackageFields): boolean {
  return fields["group_classes.included"] === true || fields["online_coaching.included"] === true;
}

/** Light client-side checks; the API remains the source of truth. */
export function draftIssues(draft: PackageDraft): DraftIssue[] {
  const issues: DraftIssue[] = [];
  if (draft.name.trim() === "") issues.push({ field: "name", message: "pkgErrorNameRequired" });
  if (priceCents(draft.price) === null) issues.push({ field: "price", message: "pkgErrorPriceRequired" });
  if (!anyServiceIncluded(draft.fields)) {
    issues.push({ field: "group_classes.included", message: "pkgErrorServiceRequired" });
  }
  if (ONE_OFF_TYPES.has(draft.packageType) && !draft.fields["terms.validity"]) {
    issues.push({ field: "terms.validity", message: "pkgErrorValidityRequired" });
  }
  const visits = draft.fields["group_classes.visits"] as QuotaValue | undefined;
  if (
    draft.fields["group_classes.included"] === true &&
    visits &&
    typeof visits.limit === "number" &&
    visits.limit < 1
  ) {
    issues.push({ field: "group_classes.visits", message: "pkgErrorVisitsPositive" });
  }
  const coaching = draft.fields["online_coaching.included"] === true;
  if (coaching && !draft.fields["online_coaching.assigned_programming"] && !draft.fields["online_coaching.messaging"]) {
    issues.push({ field: "online_coaching.included", message: "pkgErrorCoachingChannel" });
  }
  return issues;
}

export function toPackageRequest(catalog: PackageCatalog, draft: PackageDraft) {
  const fields = Object.fromEntries(
    catalog.fields.filter((field) => field.available).map((field) => [field.key, draft.fields[field.key]]),
  );
  return {
    name: draft.name.trim(),
    description: draft.description.trim() || null,
    package_type: draft.packageType,
    billing_period: draft.billingPeriod,
    base_price_cents: priceCents(draft.price) ?? 0,
    tags: draft.tags,
    fields,
  };
}

export function draftFromPackage(catalog: PackageCatalog, pkg: FinanceRecord): PackageDraft {
  const typeKey = String(pkg.package_type ?? "membership");
  const type = findType(catalog, typeKey);
  const billingPeriod = String(pkg.billing_period ?? type?.default_billing_period ?? "monthly");
  const fields = (pkg.fields as PackageFields | undefined) ?? (type ? presetFor(type, billingPeriod) : {});
  const cents = typeof pkg.base_price_cents === "number" ? pkg.base_price_cents : Number(pkg.base_price_cents ?? 0);
  return {
    packageType: typeKey,
    billingPeriod,
    name: String(pkg.name ?? ""),
    description: String(pkg.description ?? ""),
    price: (cents / 100).toFixed(2).replace(/\.00$/, ""),
    tags: Array.isArray(pkg.tags) ? pkg.tags.map(String) : [],
    fields,
  };
}

/** Monthly equivalent shown under recurring prices that are not monthly. */
export function monthlyEquivalentCents(billingPeriod: string, cents: number | null): number | null {
  const months: Record<string, number> = { quarterly: 3, semiannual: 6, annual: 12 };
  if (cents === null || !months[billingPeriod]) return null;
  return Math.round(cents / months[billingPeriod]);
}

export function perVisitCents(draft: PackageDraft): number | null {
  const cents = priceCents(draft.price);
  const visits = draft.fields["group_classes.visits"] as QuotaValue | undefined;
  if (cents === null || !visits || typeof visits.limit !== "number" || visits.limit < 1) return null;
  if (!ONE_OFF_TYPES.has(draft.packageType)) return null;
  return Math.round(cents / visits.limit);
}

/** Wizard steps for a type (relevant steps only). */
export function wizardSteps(typeKey: string): Array<"type" | "basics" | "included" | "review"> {
  return typeKey === "drop_in" ? ["type", "basics", "review"] : ["type", "basics", "included", "review"];
}

/** Message key for a catalog field label, for example `pkgFieldGroupClassesVisits`. */
export function fieldLabelKey(fieldKey: string): string {
  return "pkgField" + fieldKey.split(/[._]/).map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join("");
}

export function sectionLabelKey(section: string): string {
  return "pkgSection" + section.split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join("");
}

export function typeLabelKey(typeKey: string): string {
  return "pkgType" + typeKey.split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join("");
}

export function lockReasonKey(reason: string): string {
  return "pkgLockReason" + reason.split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join("");
}

export type SummaryLine = { key: string; params?: Record<string, string | number> };

/** Member-facing description of a draft, as message keys plus parameters. */
export function memberSummary(draft: PackageDraft, classTypeNames: Map<string, string>): SummaryLine[] {
  const lines: SummaryLine[] = [];
  const fields = draft.fields;

  if (fields["group_classes.included"] === true) {
    const visits = fields["group_classes.visits"] as QuotaValue;
    if (visits.limit === "unlimited") {
      lines.push({ key: visits.period === "subscription_period" ? "pkgSummaryVisitsUnlimited" : `pkgSummaryVisitsUnlimitedPer_${visits.period}` });
    } else {
      lines.push({
        key: visits.period === "subscription_period" ? "pkgSummaryVisitsTotal" : `pkgSummaryVisitsPer_${visits.period}`,
        params: { count: visits.limit },
      });
    }

    const scope = fields["group_classes.class_types"];
    if (Array.isArray(scope)) {
      lines.push({
        key: "pkgSummaryClassTypesOnly",
        params: { names: scope.map((id) => classTypeNames.get(String(id)) ?? "?").join(", ") },
      });
    } else {
      lines.push({ key: "pkgSummaryClassTypesAll" });
    }

    for (const limit of (fields["group_classes.class_type_limits"] as ClassTypeLimit[] | undefined) ?? []) {
      lines.push({
        key: `pkgSummaryClassTypeLimit_${limit.period}`,
        params: { name: classTypeNames.get(limit.id) ?? "?", count: limit.limit },
      });
    }
  }

  if (fields["online_coaching.included"] === true) {
    if (fields["online_coaching.assigned_programming"] === true) lines.push({ key: "pkgSummaryAssignedProgramming" });
    if (fields["online_coaching.messaging"] === true) lines.push({ key: "pkgSummaryCoachMessaging" });
    const touchpoints = fields["online_coaching.touchpoints"] as QuotaValue | undefined;
    if (touchpoints && touchpoints.limit !== "unlimited") {
      lines.push({ key: `pkgSummaryCheckIns_${touchpoints.period}`, params: { count: touchpoints.limit } });
    }
  }

  const amenities = (fields["facility.amenities"] as string[] | undefined) ?? [];
  if (amenities.length > 0) lines.push({ key: "pkgSummaryAmenities", params: { list: amenities.join("|") } });
  if (typeof fields["facility.amenities_note"] === "string" && fields["facility.amenities_note"]) {
    lines.push({ key: "pkgSummaryAmenitiesNote", params: { note: String(fields["facility.amenities_note"]) } });
  }

  const validity = fields["terms.validity"] as DurationValue | null | undefined;
  if (validity) lines.push({ key: `pkgSummaryValidity_${validity.unit}`, params: { count: validity.amount } });
  if (fields["terms.once_per_person"] === true) lines.push({ key: "pkgSummaryOncePerPerson" });
  if (fields["terms.new_members_only"] === true) lines.push({ key: "pkgSummaryNewMembersOnly" });
  if (draft.packageType === "membership" && fields["terms.auto_renew"] === false) lines.push({ key: "pkgSummaryNoAutoRenew" });
  return lines;
}
