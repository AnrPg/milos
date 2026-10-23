import { NO_RULES, type PerkMethod, type PerkStatus, type StaffPerk, type StaffPerkInput } from "@/api/perks";

/**
 * Partner perk rules the screens need (ADR-191, mirroring `PerkRules` on the
 * API), pure: where a perk stands on a day, what a staff draft is missing,
 * which «Περισσότεροι όροι» sections are set, and reading a batch of the
 * partner's unique codes. Days are `YYYY-MM-DD` in the box's calendar,
 * compared as strings.
 */

/** The status a reader sees: a published perk past its window reads as expired, one not started yet as scheduled. */
export type PerkPhase = PerkStatus | "scheduled";

export function perkPhase(perk: { status: PerkStatus; valid_from: string | null; valid_until: string | null }, today: string): PerkPhase {
  if (perk.status !== "published") return perk.status;
  if (perk.valid_until && today > perk.valid_until) return "expired";
  if (perk.valid_from && today < perk.valid_from) return "scheduled";
  return "published";
}

/** Days left until it ends (0 = ends today); null without an end. */
export function perkDaysLeft(validUntil: string | null, today: string) {
  if (!validUntil) return null;
  const day = (value: string) => Date.UTC(Number(value.slice(0, 4)), Number(value.slice(5, 7)) - 1, Number(value.slice(8, 10)));
  return Math.round((day(validUntil) - day(today)) / 86_400_000);
}

/** Today in the device's calendar, `YYYY-MM-DD`. */
export function localToday(now: Date = new Date()) {
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}

/** Upper case, no spaces (as `PromotionCode.normalize_code`). Greek upper case drops the accents. */
export function normalizePerkCode(raw: string) {
  return raw.trim().replace(/\s+/g, "").toLocaleUpperCase("el");
}

export const PERK_CODE_PATTERN = /^[\p{Lu}\p{N}_.-]{1,64}$/u;

/** Methods where the member is handed a code to show or type. */
export function methodShowsCode(method: PerkMethod) {
  return method === "shared_code" || method === "unique_code" || method === "partner_link";
}

export function emptyPerkDraft(currency = "EUR"): StaffPerkInput {
  return {
    partner_name: "",
    partner_url: null,
    partner_address: null,
    logo_media_id: null,
    benefit_type: "percent",
    benefit_value: null,
    benefit_text: null,
    currency,
    redemption_method: "shared_code",
    shared_code: null,
    terms: null,
    valid_from: null,
    valid_until: null,
    max_claims: null,
    max_claims_per_member: 1,
    audience: "all_clients",
    package_ids: [],
    all_locations: true,
    location_ids: [],
    rules: NO_RULES,
    box_benefits: false,
  };
}

export function draftFromPerk(perk: StaffPerk): StaffPerkInput {
  return {
    partner_name: perk.partner_name,
    partner_url: perk.partner_url,
    partner_address: perk.partner_address,
    logo_media_id: perk.logo_media_id,
    benefit_type: perk.benefit_type,
    benefit_value: perk.benefit_value,
    benefit_text: perk.benefit_text,
    currency: perk.currency,
    redemption_method: perk.redemption_method,
    shared_code: perk.shared_code,
    terms: perk.terms,
    valid_from: perk.valid_from,
    valid_until: perk.valid_until,
    max_claims: perk.max_claims,
    max_claims_per_member: perk.max_claims_per_member,
    audience: perk.audience,
    package_ids: perk.package_ids,
    all_locations: perk.all_locations,
    location_ids: perk.location_ids,
    rules: { ...NO_RULES, ...(perk.rules ?? {}) },
    box_benefits: perk.box_benefits ?? false,
  };
}

export type PerkDraftProblem =
  | "partnerName"
  | "percent"
  | "amount"
  | "benefitText"
  | "code"
  | "partnerUrl"
  | "dates"
  | "hours"
  | "packages"
  | "branches"
  | "maxClaims"
  | "perMember"
  | "minSpend";

const positiveInteger = (value: number | null) => value !== null && Number.isInteger(value) && value > 0;

/** What the form must fix before saving; the API checks the same (`Perk.validate`). */
export function perkDraftProblems(draft: StaffPerkInput): PerkDraftProblem[] {
  const problems: PerkDraftProblem[] = [];
  if (!draft.partner_name.trim()) problems.push("partnerName");
  if (draft.benefit_type === "percent" && !(positiveInteger(draft.benefit_value) && draft.benefit_value! <= 100)) problems.push("percent");
  if (draft.benefit_type === "fixed_amount" && !positiveInteger(draft.benefit_value)) problems.push("amount");
  if (draft.benefit_type === "free_text" && !draft.benefit_text?.trim()) problems.push("benefitText");
  const needsCode = draft.redemption_method === "shared_code" || draft.redemption_method === "partner_link";
  if (needsCode && !PERK_CODE_PATTERN.test(normalizePerkCode(draft.shared_code ?? ""))) problems.push("code");
  const url = draft.partner_url?.trim() ?? "";
  if ((url && !/^https?:\/\/\S+$/i.test(url)) || (draft.redemption_method === "partner_link" && !url)) problems.push("partnerUrl");
  if (draft.valid_from && draft.valid_until && draft.valid_until < draft.valid_from) problems.push("dates");
  const { time_from: from, time_until: until } = draft.rules;
  if (Boolean(from) !== Boolean(until) || (from && until && until <= from)) problems.push("hours");
  if (draft.audience === "packages" && draft.package_ids.length === 0) problems.push("packages");
  if (!draft.all_locations && draft.location_ids.length === 0) problems.push("branches");
  if (draft.max_claims !== null && !positiveInteger(draft.max_claims)) problems.push("maxClaims");
  if (!positiveInteger(draft.max_claims_per_member) || draft.max_claims_per_member > 1000) problems.push("perMember");
  if (draft.rules.min_spend_cents !== null && !positiveInteger(draft.rules.min_spend_cents)) problems.push("minSpend");
  return problems;
}

/**
 * Publishing: a demo business may draft but not go live (ADR-184), and a
 * pool of unique codes needs a free code (`freeCodes`: the pool's free codes
 * plus what the form is about to add).
 */
export function canPublishPerk(draft: StaffPerkInput, activation: string | null | undefined, freeCodes = 0) {
  if (activation === "demo" || perkDraftProblems(draft).length > 0) return false;
  return draft.redemption_method !== "unique_code" || freeCodes > 0;
}

/** The collapsed «Περισσότεροι όροι» sections and whether each holds anything. */
export type RuleSection = "limits" | "when" | "who" | "where" | "terms";

export function ruleSectionsSet(draft: StaffPerkInput): Record<RuleSection, boolean> {
  const { rules } = draft;
  return {
    limits: draft.max_claims !== null || draft.max_claims_per_member !== 1 || rules.min_spend_cents !== null,
    when: rules.weekdays.length > 0 || Boolean(rules.time_from),
    who: draft.audience === "packages" || !draft.all_locations || rules.new_customers_only,
    where: rules.channel !== null || Boolean(draft.partner_address?.trim()),
    terms: Boolean(draft.terms?.trim()) || draft.box_benefits,
  };
}

export const MAX_CODES_PER_UPLOAD = 5000;

/**
 * Reads the partner's unique codes from pasted text or a CSV/TXT file: one
 * per line, or separated by commas, semicolons or tabs; a first-line header
 * such as «code» is skipped. Repeats count once; malformed ones are reported.
 */
export function parsePerkCodes(text: string) {
  const codes: string[] = [];
  const seen = new Set<string>();
  let duplicates = 0;
  let invalid = 0;
  const tokens = text.split(/[\r\n,;\t]+/).map((token) => token.trim().replace(/^["']|["']$/g, ""));
  let first = true;
  for (const token of tokens) {
    const code = normalizePerkCode(token);
    if (!code) continue;
    const header = first && /^(CODE|CODES|ΚΩΔΙΚΟΣ|ΚΩΔΙΚΟΙ)$/u.test(code);
    first = false;
    if (header) continue;
    if (!PERK_CODE_PATTERN.test(code)) {
      invalid += 1;
      continue;
    }
    if (seen.has(code)) {
      duplicates += 1;
      continue;
    }
    seen.add(code);
    codes.push(code);
  }
  return { codes: codes.slice(0, MAX_CODES_PER_UPLOAD), duplicates, invalid, tooMany: codes.length > MAX_CODES_PER_UPLOAD };
}

/** How many of the pool's codes members hold. */
export function codesHandedOut(codes: { total: number; free: number }) {
  return Math.max(0, codes.total - codes.free);
}
