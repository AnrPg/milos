import { ApiError, apiRequest } from "@/api/client";

/**
 * Partner perks (ADR-191): offers of partner businesses that the box
 * publishes for its own clients (never in Γύρω μου). Members claim them in
 * Εγώ › Πληρωμές › Προσφορές; staff manage them in Οικονομικά › Προσφορές ›
 * Συνεργατών. How the store redeems one is up to the partner
 * (`redemption_method`):
 *   - partner-issued, checked in the partner's own system: `shared_code`
 *     (one code for everybody, the default), `code_pool` (the partner's
 *     single-use codes, pasted or uploaded and topped up; a claim hands one
 *     out), `partner_link` (an online store link with the code applied) and
 *     `show_membership` (no code);
 *   - Palee-issued: `personal_qr`, a single-use QR whose signed public link
 *     (`/perks/verify/{token}`, no login) the store opens to mark it used.
 * What a perk gives (`benefit`), when and for whom it holds (`rules`) and what
 * the method needs (`redemption`) are versioned documents: a claim keeps the
 * version the member agreed to.
 *
 * Shapes follow PaleeWeb.Schemas.Perks on the perks-api branch.
 * TODO(ADR-191): alias them to `components["schemas"]` once
 * `npm run generate:api` (needs `mix`) exports them.
 */

export type PerkBenefitType = "percent" | "fixed_amount" | "free_item" | "buy_x_get_y" | "free_text";
export type PerkMethod = "shared_code" | "code_pool" | "partner_link" | "show_membership" | "personal_qr";
export type PerkStatus = "draft" | "published" | "paused" | "expired";
export type PerkChannel = "in_store" | "online" | "both";
export type PerkPeriod = "day" | "week" | "month";
export type PerkClaimStatus = "claimed" | "used" | "revoked";

/** What a perk gives (`PerkBenefit`); which fields count depends on `type`. */
export type PerkBenefit = {
  type: PerkBenefitType;
  percent?: number | null;
  amount_cents?: number | null;
  currency?: string | null;
  item?: string | null;
  buy_quantity?: number | null;
  get_quantity?: number | null;
  /** The gift for `free_text`; an optional note («σε όλα τα συμπληρώματα») for the others. */
  text?: string | null;
  min_spend_cents?: number | null;
  /** A cap; it only means something for a percent. */
  max_discount_cents?: number | null;
};

/** A weekly window in the business's local time; `HH:MM:SS`. */
export type PerkWindow = { weekdays: number[]; starts_at: string; ends_at: string };

export type PerkLimits = {
  max_claims?: number | null;
  max_per_member?: number;
  period?: PerkPeriod | null;
  max_per_period?: number | null;
  max_per_member_per_period?: number | null;
};

/** Empty lists mean everyone; memberships are packages. */
export type PerkEligibility = { package_ids?: string[]; group_ids?: string[]; min_tenure_days?: number | null };

/** When and for whom a perk holds (`PerkRules`). */
export type PerkRules = {
  valid_from?: string | null;
  valid_until?: string | null;
  channel?: PerkChannel;
  /** How it combines with other offers, in words. */
  stacking?: string | null;
  /** None means always. */
  recurring?: PerkWindow[];
  limits?: PerkLimits;
  eligibility?: PerkEligibility;
};

/** What the method needs (`PerkRedemptionSettings`). */
export type PerkRedemption = {
  shared_code?: string | null;
  /** partner_link: https; `{code}` in it is replaced by the code. */
  link_url?: string | null;
  low_pool_threshold?: number | null;
  instructions?: string | null;
};

/** What every reader of a perk sees. */
export type PerkCommon = {
  id: string;
  organization_id: string;
  partner_name: string;
  partner_url: string | null;
  partner_address: string | null;
  logo_media_id: string | null;
  logo_url: string | null;
  redemption_method: PerkMethod;
  version: number;
  benefit: PerkBenefit;
  /** The API's one-line label (`10%`, `5.00 EUR`, `Free shaker`); the app words it itself. */
  benefit_label: string;
  rules: PerkRules;
  terms: string | null;
  instructions: string | null;
  valid_from: string | null;
  valid_until: string | null;
  status: PerkStatus;
};

export type PerkProvider = { organization_id: string; name: string | null; slug: string | null; kind?: "gym" | "coach"; logo_url: string | null };

export type PerkVerificationLink = { token: string; path: string; expires_at: string };

export type PerkClaim = {
  id: string;
  perk_id: string;
  perk_version: number;
  organization_id: string;
  provider: PerkProvider;
  partner_name: string;
  benefit_label: string;
  redemption_method: PerkMethod;
  terms: string | null;
  instructions: string | null;
  valid_until: string | null;
  partner_url: string | null;
  /** What to give the partner: the shared code, the pool code, the code under the QR; null for show_membership. */
  code: string | null;
  reference: string;
  /** partner_link: the store link with the code applied. */
  url: string | null;
  show_membership: boolean;
  status: PerkClaimStatus;
  usable: boolean;
  claimed_at: string;
  used_at: string | null;
  /** personal_qr: the signed link, right after claiming or refreshing it. */
  verification: PerkVerificationLink | null;
};

export type PerkUnavailableReason =
  | "perk_sold_out"
  | "perk_period_sold_out"
  | "perk_member_limit"
  | "perk_member_period_limit"
  | "perk_outside_hours"
  | "perk_not_available";

export type MemberPerk = PerkCommon & {
  provider: PerkProvider;
  claimable: boolean;
  unavailable_reason: PerkUnavailableReason | null;
  /** The member's unused claim. */
  claim: PerkClaim | null;
};

export type PerkCodePool = { total: number; free: number; low: boolean };

export type StaffPerk = PerkCommon & {
  redemption: PerkRedemption;
  all_locations: boolean;
  location_ids: string[];
  /** Members who claimed it (opened the code). */
  claims_count: number;
  uses_count: number;
  /** Left under the overall cap; null when uncapped. */
  remaining: number | null;
  /** The code pool of a code_pool perk; null for the other methods. */
  codes: PerkCodePool | null;
  published_at: string | null;
};

/** What staff send (`PerkCreate` / `PerkUpdate`, no extra fields allowed). */
export type StaffPerkInput = {
  partner_name: string;
  partner_url: string | null;
  partner_address: string | null;
  logo_media_id: string | null;
  redemption_method: PerkMethod;
  all_locations: boolean;
  location_ids: string[];
  benefit: PerkBenefit;
  rules: PerkRules;
  redemption: PerkRedemption;
  terms: string | null;
};

export type PerkCodesResult = PerkCodePool & { added: number; duplicates: number };

export type PerkCheckStatus = "valid" | "used" | "revoked" | "expired" | "outside_hours";

/** What the store sees on a member's QR link (`PerkVerification`). */
export type PerkCheck = {
  status: PerkCheckStatus;
  code: string;
  member_first_name: string | null;
  claimed_at: string;
  used_at: string | null;
  perk: { partner_name: string; benefit_label: string; terms: string | null; valid_until: string | null };
  business: { name: string | null; logo_url: string | null };
};

const id = (value: string) => encodeURIComponent(value);

export const perkKeys = {
  member: ["me", "perks"] as const,
  staff: ["admin", "perks"] as const,
  check: (token: string) => ["perk-check", token] as const,
};

/** A route an older API does not serve answers 404; lists then read as empty instead of failing. */
export function isMissingEndpoint(error: unknown) {
  return error instanceof ApiError && error.status === 404;
}

// Member (account-wide: every provider the person is a client of) ------------

/** GET /api/me/perks */
export async function fetchMemberPerks(token: string) {
  try {
    const data = await apiRequest<{ perks?: MemberPerk[] }>("/me/perks", { token, scope: "account" });
    return data.perks ?? [];
  } catch (error) {
    if (isMissingEndpoint(error)) return [];
    throw error;
  }
}

/** POST /api/me/perks/{id}/claim: claims a perk, or returns the open claim of it (safe to repeat). */
export async function claimPerk(token: string, perkId: string) {
  return apiRequest<{ claim: PerkClaim; created?: boolean }>(`/me/perks/${id(perkId)}/claim`, { method: "POST", token, scope: "account" });
}

/** POST /api/me/perks/claims/{id}/verification-link: a fresh short-lived QR link; the previous one stops working. */
export async function refreshPerkLink(token: string, claimId: string) {
  const data = await apiRequest<{ claim: PerkClaim }>(`/me/perks/claims/${id(claimId)}/verification-link`, {
    method: "POST",
    token,
    scope: "account",
  });
  return data.claim;
}

// Staff (Οικονομικά › Προσφορές › Συνεργατών) --------------------------------

/** GET /api/org/{slug}/admin/perks */
export async function fetchStaffPerks(token: string) {
  try {
    const data = await apiRequest<{ perks?: StaffPerk[] }>("/admin/perks", { token });
    return data.perks ?? [];
  } catch (error) {
    if (isMissingEndpoint(error)) return [];
    throw error;
  }
}

/** POST /api/org/{slug}/admin/perks (a new draft) */
export async function createStaffPerk(token: string, body: StaffPerkInput) {
  const data = await apiRequest<{ perk: StaffPerk }>("/admin/perks", { method: "POST", token, body });
  return data.perk;
}

/** PATCH /api/org/{slug}/admin/perks/{id}: amends the version until the first claim, then makes a new one. */
export async function updateStaffPerk(token: string, perkId: string, body: Partial<StaffPerkInput>) {
  const data = await apiRequest<{ perk: StaffPerk }>(`/admin/perks/${id(perkId)}`, { method: "PATCH", token, body });
  return data.perk;
}

/** POST …/admin/perks/{id}/publish|pause|expire. Publish is going live: a demo business gets 403 `business_not_activated`. */
export async function stepStaffPerk(token: string, perkId: string, step: "publish" | "pause" | "expire") {
  const data = await apiRequest<{ perk: StaffPerk }>(`/admin/perks/${id(perkId)}/${step}`, { method: "POST", token });
  return data.perk;
}

/** POST …/admin/perks/{id}/codes: adds a batch of the partner's codes; repeats are skipped. */
export async function addPerkCodes(token: string, perkId: string, codes: string[]) {
  return apiRequest<PerkCodesResult>(`/admin/perks/${id(perkId)}/codes`, { method: "POST", token, body: { codes } });
}

// The store's check page (public, no login) -----------------------------------

/** GET /api/public/perk-verifications/{token} */
export async function fetchPerkCheck(token: string) {
  return apiRequest<PerkCheck>(`/public/perk-verifications/${id(token)}`, { scope: "account" });
}

/** POST /api/public/perk-verifications/{token}/redeem: «Σημείωση ως χρησιμοποιημένο», once. */
export async function redeemPerkCheck(token: string) {
  return apiRequest<PerkCheck>(`/public/perk-verifications/${id(token)}/redeem`, { method: "POST", scope: "account" });
}
