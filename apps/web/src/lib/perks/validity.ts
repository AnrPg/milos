import type { PerkOfferKind, PerkStatus, StaffPerkInput } from "@/api/perks";

/**
 * Partner perk rules the screens need (ADR-191), pure: where a perk stands
 * on a given day, whether a member still sees it, and what a staff draft is
 * missing before it can be saved or published. Days are `YYYY-MM-DD` in the
 * box's calendar, compared as strings.
 */

export type PerkPhase = "draft" | "paused" | "ended" | "scheduled" | "active" | "expired";

export function perkPhase(perk: { status: PerkStatus; starts_on: string | null; ends_on: string | null }, today: string): PerkPhase {
  if (perk.status === "draft") return "draft";
  if (perk.status === "paused") return "paused";
  if (perk.status === "ended") return "ended";
  if (perk.starts_on && today < perk.starts_on) return "scheduled";
  if (perk.ends_on && today > perk.ends_on) return "expired";
  return "active";
}

/** A member sees a perk only while it is live today. */
export function isPerkLive(perk: { starts_on: string | null; ends_on: string | null }, today: string) {
  return perkPhase({ ...perk, status: "active" }, today) === "active";
}

/** Days left until it ends (0 = ends today); null without an end. */
export function perkDaysLeft(endsOn: string | null, today: string) {
  if (!endsOn) return null;
  const end = Date.UTC(Number(endsOn.slice(0, 4)), Number(endsOn.slice(5, 7)) - 1, Number(endsOn.slice(8, 10)));
  const now = Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 1, Number(today.slice(8, 10)));
  return Math.round((end - now) / 86_400_000);
}

/** Today in the device's calendar, `YYYY-MM-DD`. */
export function localToday(now: Date = new Date()) {
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}

export const PERK_CODE_PATTERN = /^[\p{Lu}\p{N}_-]{3,32}$/u;

/** A shared code is upper case, letters (Greek too), digits, `-` and `_`. */
export function normalizePerkCode(raw: string) {
  return raw.trim().replace(/\s+/g, "").toLocaleUpperCase("el");
}

export type PerkDraftProblem =
  | "partnerName"
  | "offerText"
  | "percent"
  | "amount"
  | "code"
  | "dates"
  | "packages"
  | "branches"
  | "perMemberLimit"
  | "totalLimit";

function positiveIntegerOrNull(value: number | null) {
  return value === null || (Number.isInteger(value) && value > 0);
}

function validOfferValue(kind: PerkOfferKind, value: number | null) {
  if (kind === "percent") return value !== null && Number.isInteger(value) && value >= 1 && value <= 100;
  if (kind === "amount") return value !== null && Number.isInteger(value) && value > 0;
  return true;
}

/** What the form must fix; empty when the perk can be saved. */
export function perkDraftProblems(draft: StaffPerkInput): PerkDraftProblem[] {
  const problems: PerkDraftProblem[] = [];
  if (!draft.partner.name.trim()) problems.push("partnerName");
  if (!draft.offer.text.trim()) problems.push("offerText");
  if (!validOfferValue(draft.offer.kind, draft.offer.value)) problems.push(draft.offer.kind === "percent" ? "percent" : "amount");
  if (draft.code_mode === "shared" && !PERK_CODE_PATTERN.test(normalizePerkCode(draft.shared_code ?? ""))) problems.push("code");
  if (draft.starts_on && draft.ends_on && draft.ends_on < draft.starts_on) problems.push("dates");
  if (draft.audience === "packages" && draft.package_ids.length === 0) problems.push("packages");
  if (!draft.all_locations && draft.location_ids.length === 0) problems.push("branches");
  if (!positiveIntegerOrNull(draft.per_member_limit)) problems.push("perMemberLimit");
  if (!positiveIntegerOrNull(draft.total_limit)) problems.push("totalLimit");
  return problems;
}

/** Publishing: a demo business may draft but not go live (ADR-184). */
export function canPublishPerk(draft: StaffPerkInput, activation: string | null | undefined) {
  return activation !== "demo" && perkDraftProblems(draft).length === 0;
}
