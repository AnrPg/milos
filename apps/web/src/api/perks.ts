import { ApiError, apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

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
 * Shapes alias the generated OpenAPI schemas (PaleeWeb.Schemas.Perks).
 */

type Schemas = components["schemas"];

/** What a perk gives (`PerkBenefit`); which fields count depends on `type`. */
export type PerkBenefit = Schemas["PerkBenefit"];
export type PerkBenefitType = PerkBenefit["type"];
export type StaffPerk = Schemas["StaffPerk"];
export type MemberPerk = Schemas["MemberPerk"];
export type PerkClaim = Schemas["MemberPerkClaim"];
export type PerkMethod = StaffPerk["redemption_method"];
export type PerkStatus = StaffPerk["status"];
/** When and for whom a perk holds (`PerkRules`). */
export type PerkRules = Schemas["PerkRules"];
export type PerkChannel = NonNullable<PerkRules["channel"]>;
/** A weekly window in the business's local time; `HH:MM:SS`. */
export type PerkWindow = Schemas["PerkRecurringWindow"];
export type PerkLimits = Schemas["PerkLimits"];
export type PerkPeriod = NonNullable<PerkLimits["period"]>;
/** Empty lists mean everyone; memberships are packages, groups are member groups. */
export type PerkEligibility = Schemas["PerkEligibility"];
/** What the method needs (`PerkRedemptionSettings`). */
export type PerkRedemption = Schemas["PerkRedemptionSettings"];
export type PerkProvider = Schemas["PerkProvider"];
export type PerkVerificationLink = NonNullable<Schemas["PerkVerificationLink"]>;
export type PerkClaimStatus = PerkClaim["status"];
export type PerkUnavailableReason = NonNullable<MemberPerk["unavailable_reason"]>;
export type PerkCodePool = NonNullable<Schemas["PerkCodePool"]>;
export type PerkCodesResult = Schemas["PerkCodesResult"];
/** What staff send (`PerkCreate`; `PerkUpdate` takes the same fields, all optional; no extra fields allowed). */
export type StaffPerkInput = Schemas["PerkCreate"];
/** What the store sees on a member's QR link (`PerkVerification`). */
export type PerkCheck = Schemas["PerkVerification"];
export type PerkCheckStatus = PerkCheck["status"];

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
