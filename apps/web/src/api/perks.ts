import { ApiError, apiRequest } from "@/api/client";

/**
 * Partner perks (ADR-191): offers of partner businesses that the box
 * publishes for its own clients (never in Γύρω μου). Members claim them in
 * Εγώ › Πληρωμές › Προσφορές; staff manage them in Οικονομικά › Προσφορές ›
 * Συνεργατών. How the store redeems one is up to the partner:
 *   - `shared_code`: one code for everybody;
 *   - `unique_code`: a pool of the partner's single-use codes, pasted or
 *     uploaded and topped up; a claim hands one out;
 *   - `qr`: a personal Palee QR; the store opens its signed public link
 *     (`/perks/verify/{token}`, no login) and marks it used;
 *   - `partner_link`, `show_membership`: see TODO below.
 *
 * Shapes follow `PerkPresenter`, `MemberPerks` and `PerkVerification` on
 * the perks-api branch (no controllers or OpenAPI yet).
 * TODO(ADR-191): swap for `components["schemas"]` once `npm run generate:api`
 * exports them, and confirm the routes named next to each call.
 * TODO(ADR-191): `partner_link` (the partner's link with the code applied),
 * `show_membership` (the member shows their Palee membership), `rules`
 * (recurring windows, channel, eligibility) and `box_benefits` are not in the
 * API's domain yet; the form sends them so the API can take them on without
 * a web change.
 */

export type PerkBenefitType = "percent" | "fixed_amount" | "free_text";
export type PerkMethod = "shared_code" | "unique_code" | "qr" | "partner_link" | "show_membership";
export type PerkStatus = "draft" | "published" | "paused" | "expired";
export type PerkAudience = "all_clients" | "packages";
export type PerkChannel = "in_store" | "online" | "both";

/** Conditions beyond the window and the caps; all optional. */
export type PerkRules = {
  /** ISO weekdays 1 (Monday) … 7 the perk holds on; empty = every day. */
  weekdays: number[];
  /** `HH:MM` local to the partner; both or neither. */
  time_from: string | null;
  time_until: string | null;
  channel: PerkChannel | null;
  /** Only for someone who is new to the partner. */
  new_customers_only: boolean;
  /** Spend at least this much (cents) for it to apply. */
  min_spend_cents: number | null;
};

export const NO_RULES: PerkRules = { weekdays: [], time_from: null, time_until: null, channel: null, new_customers_only: false, min_spend_cents: null };

/** What every reader of a perk sees (`PerkPresenter.common`). */
export type PerkCommon = {
  id: string;
  organization_id: string;
  partner_name: string;
  partner_url: string | null;
  partner_address: string | null;
  logo_media_id: string | null;
  logo_url: string | null;
  benefit_type: PerkBenefitType;
  /** Percent 1..100, or cents for a fixed amount. */
  benefit_value: number | null;
  benefit_text: string | null;
  /** The API's one-line label: `10%`, `5.00 EUR` or the text. */
  benefit_label: string;
  currency: string;
  redemption_method: PerkMethod;
  terms: string | null;
  valid_from: string | null;
  valid_until: string | null;
  status: PerkStatus;
  rules?: PerkRules | null;
  box_benefits?: boolean;
};

export type PerkProvider = { organization_id: string; name: string; slug: string | null; kind: string; logo_url: string | null };

export type PerkVerificationLink = { token: string; path: string; expires_at: string };

export type PerkClaim = {
  id: string;
  perk_id: string;
  organization_id: string;
  provider: PerkProvider;
  partner_name: string;
  benefit_label: string;
  redemption_method: PerkMethod;
  terms: string | null;
  valid_until: string | null;
  partner_url: string | null;
  /** The code (shared or from the pool); for a QR claim, the short code under it. */
  code: string | null;
  status: "claimed" | "used" | "revoked";
  usable: boolean;
  claimed_at: string;
  used_at: string | null;
  /** A QR claim's signed link, only right after claiming or refreshing it. */
  verification: PerkVerificationLink | null;
};

export type MemberPerk = PerkCommon & {
  provider: PerkProvider;
  claimable: boolean;
  /** `perk_sold_out`, `perk_member_limit`, … when it cannot be claimed now. */
  unavailable_reason: string | null;
  claim: PerkClaim | null;
};

export type StaffPerk = PerkCommon & {
  shared_code: string | null;
  max_claims: number | null;
  max_claims_per_member: number;
  audience: PerkAudience;
  package_ids: string[];
  all_locations: boolean;
  location_ids: string[];
  /** Members who claimed it (opened the code). */
  claims_count: number;
  uses_count: number;
  /** Left under `max_claims`; null when uncapped. */
  remaining: number | null;
  /** The unique-code pool; null for other methods. */
  codes: { total: number; free: number } | null;
  published_at: string | null;
};

/** What staff send to create or edit a perk (`Perk.editable_fields`, plus the pending extras). */
export type StaffPerkInput = {
  partner_name: string;
  partner_url: string | null;
  partner_address: string | null;
  logo_media_id: string | null;
  benefit_type: PerkBenefitType;
  benefit_value: number | null;
  benefit_text: string | null;
  currency: string;
  redemption_method: PerkMethod;
  shared_code: string | null;
  terms: string | null;
  valid_from: string | null;
  valid_until: string | null;
  max_claims: number | null;
  max_claims_per_member: number;
  audience: PerkAudience;
  package_ids: string[];
  all_locations: boolean;
  location_ids: string[];
  rules: PerkRules;
  box_benefits: boolean;
};

export type PerkCodesResult = { added: number; duplicates: number; total: number; free: number };

export type PerkCheckStatus = "valid" | "used" | "revoked" | "expired";

/** What the store sees on a member's QR link (`PerkVerification.present`). */
export type PerkCheck = {
  status: PerkCheckStatus;
  code: string | null;
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

/** A route the API does not serve yet answers 404; lists then read as empty instead of failing. */
export function isMissingEndpoint(error: unknown) {
  return error instanceof ApiError && error.status === 404;
}

// Member (account-wide: every provider the person is a client of) ------------

// TODO(ADR-191): GET /api/me/perks
export async function fetchMemberPerks(token: string) {
  try {
    const data = await apiRequest<{ perks?: MemberPerk[] }>("/me/perks", { token, scope: "account" });
    return data.perks ?? [];
  } catch (error) {
    if (isMissingEndpoint(error)) return [];
    throw error;
  }
}

/** Claims a perk, or returns the member's open claim of it (safe to repeat). */
// TODO(ADR-191): POST /api/me/perks/{id}/claim
export async function claimPerk(token: string, perkId: string) {
  return apiRequest<{ claim: PerkClaim; created: boolean }>(`/me/perks/${id(perkId)}/claim`, { method: "POST", token, scope: "account" });
}

/** A fresh short-lived link for a QR claim; the previous one stops working. */
// TODO(ADR-191): POST /api/me/perks/claims/{id}/verification-link
export async function refreshPerkLink(token: string, claimId: string) {
  const data = await apiRequest<{ claim: PerkClaim }>(`/me/perks/claims/${id(claimId)}/verification-link`, {
    method: "POST",
    token,
    scope: "account",
  });
  return data.claim;
}

// Staff (Οικονομικά › Προσφορές › Συνεργατών) --------------------------------

// TODO(ADR-191): GET /api/org/{slug}/admin/perks
export async function fetchStaffPerks(token: string) {
  try {
    const data = await apiRequest<{ perks?: StaffPerk[] }>("/admin/perks", { token });
    return data.perks ?? [];
  } catch (error) {
    if (isMissingEndpoint(error)) return [];
    throw error;
  }
}

// TODO(ADR-191): POST /api/org/{slug}/admin/perks (a new draft)
export async function createStaffPerk(token: string, body: StaffPerkInput) {
  const data = await apiRequest<{ perk: StaffPerk }>("/admin/perks", { method: "POST", token, body });
  return data.perk;
}

// TODO(ADR-191): PATCH /api/org/{slug}/admin/perks/{id}
export async function updateStaffPerk(token: string, perkId: string, body: Partial<StaffPerkInput>) {
  const data = await apiRequest<{ perk: StaffPerk }>(`/admin/perks/${id(perkId)}`, { method: "PATCH", token, body });
  return data.perk;
}

/** Publish is a going-live action: a demo business gets 403 `business_not_activated`. */
// TODO(ADR-191): POST /api/org/{slug}/admin/perks/{id}/publish|pause|expire
export async function stepStaffPerk(token: string, perkId: string, step: "publish" | "pause" | "expire") {
  const data = await apiRequest<{ perk: StaffPerk }>(`/admin/perks/${id(perkId)}/${step}`, { method: "POST", token });
  return data.perk;
}

/** Adds a batch of the partner's unique codes; repeats are skipped. */
// TODO(ADR-191): POST /api/org/{slug}/admin/perks/{id}/codes
export async function addPerkCodes(token: string, perkId: string, codes: string[]) {
  return apiRequest<PerkCodesResult>(`/admin/perks/${id(perkId)}/codes`, { method: "POST", token, body: { codes } });
}

// The store's check page (public, no login) -----------------------------------

// TODO(ADR-191): GET /api/public/perk-verifications/{token}
export async function fetchPerkCheck(token: string) {
  return apiRequest<PerkCheck>(`/public/perk-verifications/${id(token)}`, { scope: "account" });
}

/** «Σημείωση ως χρησιμοποιημένο»: once; a second scan answers `perk_claim_already_used`. */
// TODO(ADR-191): POST /api/public/perk-verifications/{token}/redeem
export async function redeemPerkCheck(token: string) {
  return apiRequest<PerkCheck>(`/public/perk-verifications/${id(token)}/redeem`, { method: "POST", scope: "account" });
}
