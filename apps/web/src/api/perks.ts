import { ApiError, apiRequest } from "@/api/client";

/**
 * Partner perks (ADR-191): offers of partner businesses that the box
 * publishes for its own members (never in Γύρω μου). Members find them in
 * Εγώ › Πληρωμές › Προσφορές; staff manage them in Οικονομικά › Προσφορές ›
 * Συνεργατών; a partner can check a member's QR on a public page.
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
export type PerkCodeMode = "shared" | "personal";
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
  code_mode: PerkCodeMode;
  show_qr: boolean;
  /** Shows «Συνεργασία»: the box benefits from this perk. */
  box_benefits: boolean;
  used_by_me: boolean;
};

/** A revealed perk: the code, and what its QR carries (a signed check link when the API gives one). */
export type RevealedPerk = MemberPerk & {
  code: string;
  qr_value: string;
  /** The partner's no-login check page for this member (`/perk-check/{token}`), when there is one. */
  check_url: string | null;
};

export type StaffPerk = {
  id: string;
  partner: PerkPartner & { logo_media_id: string | null };
  offer: PerkOffer;
  terms: string | null;
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
};

export type StaffPerkInput = Omit<StaffPerk, "id" | "reveals_count" | "uses_count" | "partner"> & {
  partner: Omit<StaffPerk["partner"], "logo_url">;
};

export type PerkCheckStatus = "valid" | "used" | "expired" | "invalid";

export type PerkCheck = {
  status: PerkCheckStatus;
  partner_name: string;
  box_name: string;
  offer: PerkOffer;
  /** The member as the partner may see them, «Μαρία Λ.». */
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

/** Opens the code; the API counts it as a reveal (`partner_perk_reveals`). */
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

// Partner check page (public, no login) --------------------------------------

// TODO(ADR-191): GET /perk-checks/{token}, a signed, expiring token from the member's QR.
export async function fetchPerkCheck(token: string) {
  const data = await apiRequest<{ check: PerkCheck }>(`/perk-checks/${id(token)}`, { scope: "account" });
  return data.check;
}

// TODO(ADR-191): POST /perk-checks/{token}/use
export async function markPerkCheckUsed(token: string) {
  const data = await apiRequest<{ check: PerkCheck }>(`/perk-checks/${id(token)}/use`, { method: "POST", scope: "account" });
  return data.check;
}
