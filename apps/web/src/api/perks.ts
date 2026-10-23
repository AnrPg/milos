import { ApiError, apiRequest } from "@/api/client";

/**
 * Partner perks (ADR-191): offers of partner businesses that the box
 * publishes for its own members (never in Γύρω μου). Members find them in
 * Εγώ › Πληρωμές › Προσφορές; staff manage them in Οικονομικά › Προσφορές ›
 * Συνεργατών. Two ways to redeem:
 *   1. Partner codes (default): the store gives the box one shared code or a
 *      batch of unique codes that staff paste or upload; a member claims the
 *      perk and gets the code (a unique one is handed to them once) and its QR.
 *   2. Palee QR: the member shows a personal QR; the store opens its public,
 *      signed link (no login), sees valid or used, and marks it used.
 *
 * TODO(ADR-191): no perks-api branch is pushed yet. These types follow the
 * proposal's `partner_perks` model (docs/product/2026-10-23-shop-and-perks-proposal.md
 * §4). Swap them for generated schemas once `npm run generate:api` has them.
 * The member list is read straight from `/me/perks`, not from the reserved
 * `MyBilling.perks` (whose `BillingPerk` lacks the logo, terms and disclosure
 * the detail needs); the perks-api branch may drop `BillingPerk` or keep
 * filling it for other clients.
 */

export type PerkOfferKind = "percent" | "amount" | "gift";
export type PerkStatus = "draft" | "active" | "paused" | "ended";
/** How the store redeems it: codes the partner gave the box, or a personal QR Palee issues. */
export type PerkRedemption = "partner_codes" | "palee_qr";
/** Partner codes: one code for every member, or a batch of unique codes, one per member. */
export type PerkCodeMode = "shared" | "unique";
export type PerkAudience = "all_members" | "packages";

export type PerkPartner = {
  name: string;
  category: string | null;
  address: string | null;
  url: string | null;
  logo_url: string | null;
};

export type PerkOffer = {
  kind: PerkOfferKind;
  /** Percent 1..100, or an amount in cents; null for a gift. */
  value: number | null;
  /** What it covers, «σε όλα τα συμπληρώματα» or the gift itself. */
  text: string;
  currency: string;
};

export type MemberPerk = {
  id: string;
  partner: PerkPartner;
  offer: PerkOffer;
  terms: string | null;
  starts_on: string | null;
  ends_on: string | null;
  redemption: PerkRedemption;
  code_mode: PerkCodeMode;
  show_qr: boolean;
  /** Shows «Συνεργασία»: the box benefits from this perk. */
  box_benefits: boolean;
  used_by_me: boolean;
};

/**
 * A claimed perk. Partner codes: the member's code, and its QR carries the
 * code. Palee QR: no code; the QR carries the signed check link.
 */
export type RevealedPerk = MemberPerk & {
  code: string | null;
  qr_value: string;
  /** Palee QR: the store's no-login check page (`/perk-check/{token}`). */
  check_url: string | null;
};

export type StaffPerk = {
  id: string;
  partner: PerkPartner & { logo_media_id: string | null };
  offer: PerkOffer;
  terms: string | null;
  redemption: PerkRedemption;
  code_mode: PerkCodeMode;
  shared_code: string | null;
  show_qr: boolean;
  starts_on: string | null;
  ends_on: string | null;
  audience: PerkAudience;
  package_ids: string[];
  all_locations: boolean;
  location_ids: string[];
  /** Uses one member may report; null = no limit. */
  per_member_limit: number | null;
  /** Uses in all; null = no limit. */
  total_limit: number | null;
  box_benefits: boolean;
  announce: boolean;
  status: PerkStatus;
  /** Members who opened the code. */
  reveals_count: number;
  /** Member reports plus the partner's tally. */
  uses_count: number;
  /** Unique codes: how many the box holds and how many members claimed. */
  codes_total: number;
  codes_claimed: number;
};

export type StaffPerkInput = Omit<StaffPerk, "id" | "reveals_count" | "uses_count" | "codes_total" | "codes_claimed" | "partner"> & {
  partner: Omit<StaffPerk["partner"], "logo_url">;
};

export type PerkCheckStatus = "valid" | "used" | "expired" | "invalid";

/** What the store sees when it opens a member's Palee QR. */
export type PerkCheck = {
  status: PerkCheckStatus;
  partner_name: string;
  box_name: string;
  offer: PerkOffer;
  /** The member as the store may see them, «Μαρία Λ.». */
  member_name: string | null;
  used_at: string | null;
  ends_on: string | null;
};

const id = (value: string) => encodeURIComponent(value);
const memberPath = (slug: string, path = "") => `/org/${id(slug)}/me/perks${path}`;

export const perkKeys = {
  member: (slug: string) => ["perks", slug, "member"] as const,
  revealed: (slug: string, perkId: string) => ["perks", slug, "member", perkId] as const,
  staff: ["admin", "perks"] as const,
  check: (token: string) => ["perk-check", token] as const,
};

/** A route the API does not serve yet answers 404; the screens then show nothing instead of an error. */
export function isMissingEndpoint(error: unknown) {
  return error instanceof ApiError && error.status === 404;
}

// Member --------------------------------------------------------------------

// TODO(ADR-191): GET /org/{slug}/me/perks
export async function fetchMemberPerks(token: string, slug: string) {
  try {
    const data = await apiRequest<{ perks?: MemberPerk[] }>(memberPath(slug), { token });
    return data.perks ?? [];
  } catch (error) {
    if (isMissingEndpoint(error)) return [];
    throw error;
  }
}

/**
 * Claims the perk and opens its code; the API counts a reveal
 * (`partner_perk_reveals`) and, for unique codes, hands this member one
 * code once (409 `perk_codes_exhausted` when none is left).
 */
// TODO(ADR-191): POST /org/{slug}/me/perks/{id}/reveal
export async function revealPerk(token: string, slug: string, perkId: string) {
  const data = await apiRequest<{ perk: RevealedPerk }>(memberPath(slug, `/${id(perkId)}/reveal`), { method: "POST", token });
  return data.perk;
}

/** «Το χρησιμοποίησα»: a member's self-report of a use. */
// TODO(ADR-191): POST /org/{slug}/me/perks/{id}/uses
export async function reportPerkUse(token: string, slug: string, perkId: string) {
  const data = await apiRequest<{ perk: RevealedPerk }>(memberPath(slug, `/${id(perkId)}/uses`), { method: "POST", token });
  return data.perk;
}

// Staff (Οικονομικά › Προσφορές › Συνεργατών) --------------------------------

// TODO(ADR-191): GET /admin/perks
export async function fetchStaffPerks(token: string) {
  try {
    const data = await apiRequest<{ perks?: StaffPerk[] }>("/admin/perks", { token });
    return data.perks ?? [];
  } catch (error) {
    if (isMissingEndpoint(error)) return [];
    throw error;
  }
}

// TODO(ADR-191): POST /admin/perks
export async function createStaffPerk(token: string, body: StaffPerkInput) {
  const data = await apiRequest<{ perk: StaffPerk }>("/admin/perks", { method: "POST", token, body });
  return data.perk;
}

/** Publishing (`status: "active"`) is a going-live action: a demo business gets 403 `business_not_activated`. */
// TODO(ADR-191): PATCH /admin/perks/{id}
export async function updateStaffPerk(token: string, perkId: string, body: Partial<StaffPerkInput>) {
  const data = await apiRequest<{ perk: StaffPerk }>(`/admin/perks/${id(perkId)}`, { method: "PATCH", token, body });
  return data.perk;
}

export type PerkCodesUpload = { added: number; duplicates: number; invalid: number; codes_total: number; codes_claimed: number };

/** Adds a batch of the partner's unique codes (pasted or from a file); repeats are skipped. */
// TODO(ADR-191): POST /admin/perks/{id}/codes
export async function uploadPerkCodes(token: string, perkId: string, codes: string[]) {
  const data = await apiRequest<{ upload: PerkCodesUpload }>(`/admin/perks/${id(perkId)}/codes`, { method: "POST", token, body: { codes } });
  return data.upload;
}

// The store's check page (public, no login) -----------------------------------

// TODO(ADR-191): GET /perk-checks/{token}, the signed token in the member's Palee QR.
export async function fetchPerkCheck(token: string) {
  const data = await apiRequest<{ check: PerkCheck }>(`/perk-checks/${id(token)}`, { scope: "account" });
  return data.check;
}

/** «Σημείωση ως χρησιμοποιημένο»; counts as a `partner_check` use. */
// TODO(ADR-191): POST /perk-checks/{token}/use
export async function markPerkCheckUsed(token: string) {
  const data = await apiRequest<{ check: PerkCheck }>(`/perk-checks/${id(token)}/use`, { method: "POST", scope: "account" });
  return data.check;
}
