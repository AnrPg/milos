import type {
  PerkBenefit,
  PerkBenefitType,
  PerkChannel,
  PerkMethod,
  PerkPeriod,
  PerkRules,
  PerkStatus,
  StaffPerk,
  StaffPerkInput,
} from "@/api/perks";

/**
 * Partner perk rules the screens need (ADR-191, mirroring `Palee.Perks.Benefit`,
 * `Rules` and the method strategies on the API), pure: where a perk stands on
 * a day, the staff form's flat draft and its mapping to and from the API's
 * benefit / rules / redemption documents, what a draft is missing, which
 * «Περισσότεροι όροι» sections are set, and reading a batch of the partner's
 * codes. Days are `YYYY-MM-DD` in the box's calendar, compared as strings.
 */

/** The status a reader sees: a published perk past its window reads as expired, one not started yet as scheduled. */
export type PerkPhase = PerkStatus | "scheduled";

export function perkPhase(perk: { status: PerkStatus; valid_from?: string | null; valid_until?: string | null }, today: string): PerkPhase {
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

/** `PartnerLink`: a `{code}` in the link is replaced by the code. */
export const LINK_CODE_PLACEHOLDER = "{code}";

/** Whether a method needs the shared code: always for shared_code, for partner_link only with `{code}` in the link. */
export function methodNeedsCode(method: PerkMethod, linkUrl: string | null) {
  if (method === "shared_code") return true;
  return method === "partner_link" && Boolean(linkUrl?.includes(LINK_CODE_PLACEHOLDER));
}

/** A weekly window in the form: `HH:MM`, ISO weekdays 1 (Monday) … 7. */
export type DraftWindow = { weekdays: number[]; from: string; until: string };

/** The staff form's flat draft; `toPerkInput` turns it into the API's documents. */
export type PerkDraft = {
  partner_name: string;
  partner_url: string | null;
  partner_address: string | null;
  logo_media_id: string | null;
  benefit_type: PerkBenefitType;
  percent: number | null;
  amount_cents: number | null;
  currency: string;
  item: string | null;
  buy_quantity: number | null;
  get_quantity: number | null;
  /** The gift for free_text; an optional note («σε όλα τα συμπληρώματα») for the others. */
  text: string | null;
  min_spend_cents: number | null;
  max_discount_cents: number | null;
  redemption_method: PerkMethod;
  shared_code: string | null;
  link_url: string | null;
  low_pool_threshold: number | null;
  instructions: string | null;
  valid_from: string | null;
  valid_until: string | null;
  /** null = the API's default, in store and online. */
  channel: PerkChannel | null;
  stacking: string | null;
  windows: DraftWindow[];
  max_claims: number | null;
  max_per_member: number;
  period: PerkPeriod | null;
  max_per_period: number | null;
  max_per_member_per_period: number | null;
  audience: "all_clients" | "packages";
  package_ids: string[];
  /** Club groups; on top of the packages (a member must match both when both are set). */
  groups_only: boolean;
  group_ids: string[];
  min_tenure_days: number | null;
  all_locations: boolean;
  location_ids: string[];
  terms: string | null;
};

export function emptyPerkDraft(currency = "EUR"): PerkDraft {
  return {
    partner_name: "",
    partner_url: null,
    partner_address: null,
    logo_media_id: null,
    benefit_type: "percent",
    percent: null,
    amount_cents: null,
    currency,
    item: null,
    buy_quantity: null,
    get_quantity: null,
    text: null,
    min_spend_cents: null,
    max_discount_cents: null,
    redemption_method: "shared_code",
    shared_code: null,
    link_url: null,
    low_pool_threshold: null,
    instructions: null,
    valid_from: null,
    valid_until: null,
    channel: null,
    stacking: null,
    windows: [],
    max_claims: null,
    max_per_member: 1,
    period: null,
    max_per_period: null,
    max_per_member_per_period: null,
    audience: "all_clients",
    package_ids: [],
    groups_only: false,
    group_ids: [],
    min_tenure_days: null,
    all_locations: true,
    location_ids: [],
    terms: null,
  };
}

const hhmm = (time: string) => time.slice(0, 5);
const hhmmss = (time: string) => (time.length === 5 ? `${time}:00` : time);

export function draftFromPerk(perk: StaffPerk): PerkDraft {
  const { benefit, rules, redemption } = perk;
  const limits = rules.limits ?? {};
  const packages = rules.eligibility?.package_ids ?? [];
  const groups = rules.eligibility?.group_ids ?? [];
  return {
    ...emptyPerkDraft(benefit.currency ?? "EUR"),
    partner_name: perk.partner_name,
    partner_url: perk.partner_url ?? null,
    partner_address: perk.partner_address ?? null,
    logo_media_id: perk.logo_media_id ?? null,
    benefit_type: benefit.type,
    percent: benefit.percent ?? null,
    amount_cents: benefit.amount_cents ?? null,
    item: benefit.item ?? null,
    buy_quantity: benefit.buy_quantity ?? null,
    get_quantity: benefit.get_quantity ?? null,
    text: benefit.text ?? null,
    min_spend_cents: benefit.min_spend_cents ?? null,
    max_discount_cents: benefit.max_discount_cents ?? null,
    redemption_method: perk.redemption_method,
    shared_code: redemption.shared_code ?? null,
    link_url: redemption.link_url ?? null,
    low_pool_threshold: redemption.low_pool_threshold ?? null,
    instructions: redemption.instructions ?? null,
    valid_from: rules.valid_from ?? perk.valid_from ?? null,
    valid_until: rules.valid_until ?? perk.valid_until ?? null,
    channel: rules.channel && rules.channel !== "both" ? rules.channel : null,
    stacking: rules.stacking ?? null,
    windows: (rules.recurring ?? []).map((window) => ({ weekdays: window.weekdays, from: hhmm(window.starts_at), until: hhmm(window.ends_at) })),
    max_claims: limits.max_claims ?? null,
    max_per_member: limits.max_per_member ?? 1,
    period: limits.period ?? null,
    max_per_period: limits.max_per_period ?? null,
    max_per_member_per_period: limits.max_per_member_per_period ?? null,
    audience: packages.length > 0 ? "packages" : "all_clients",
    package_ids: packages,
    groups_only: groups.length > 0,
    group_ids: groups,
    min_tenure_days: rules.eligibility?.min_tenure_days ?? null,
    all_locations: perk.all_locations,
    location_ids: perk.location_ids,
    terms: perk.terms ?? null,
  };
}

const trimmed = (value: string | null) => value?.trim() || null;

/** The benefit document: only the fields its type uses, plus the optional note and spend rules. */
function benefitOf(draft: PerkDraft): PerkBenefit {
  const benefit: PerkBenefit = { type: draft.benefit_type, text: trimmed(draft.text), min_spend_cents: draft.min_spend_cents };
  switch (draft.benefit_type) {
    case "percent":
      return { ...benefit, percent: draft.percent, max_discount_cents: draft.max_discount_cents };
    case "fixed_amount":
      return { ...benefit, amount_cents: draft.amount_cents, currency: draft.currency };
    case "free_item":
      return { ...benefit, item: trimmed(draft.item) };
    case "buy_x_get_y":
      return { ...benefit, buy_quantity: draft.buy_quantity, get_quantity: draft.get_quantity, item: trimmed(draft.item) };
    default:
      return benefit;
  }
}

/** What the API takes (`PerkCreate` / `PerkUpdate`). */
export function toPerkInput(draft: PerkDraft): StaffPerkInput {
  const rules: PerkRules = {
    valid_from: draft.valid_from,
    valid_until: draft.valid_until,
    stacking: trimmed(draft.stacking),
    recurring: draft.windows.map((window) => ({ weekdays: [...window.weekdays].sort(), starts_at: hhmmss(window.from), ends_at: hhmmss(window.until) })),
    limits: {
      max_claims: draft.max_claims,
      max_per_member: draft.max_per_member,
      period: draft.period,
      max_per_period: draft.period ? draft.max_per_period : null,
      max_per_member_per_period: draft.period ? draft.max_per_member_per_period : null,
    },
    eligibility: {
      package_ids: draft.audience === "packages" ? draft.package_ids : [],
      group_ids: draft.groups_only ? draft.group_ids : [],
      min_tenure_days: draft.min_tenure_days,
    },
    ...(draft.channel ? { channel: draft.channel } : {}),
  };
  const code = methodNeedsCode(draft.redemption_method, draft.link_url) ? normalizePerkCode(draft.shared_code ?? "") : null;
  return {
    partner_name: draft.partner_name.trim(),
    partner_url: trimmed(draft.partner_url),
    partner_address: trimmed(draft.partner_address),
    logo_media_id: draft.logo_media_id,
    redemption_method: draft.redemption_method,
    all_locations: draft.all_locations,
    location_ids: draft.all_locations ? [] : draft.location_ids,
    benefit: benefitOf(draft),
    rules,
    redemption: {
      shared_code: code,
      link_url: draft.redemption_method === "partner_link" ? trimmed(draft.link_url) : null,
      low_pool_threshold: draft.redemption_method === "code_pool" ? draft.low_pool_threshold : null,
      instructions: trimmed(draft.instructions),
    },
    terms: trimmed(draft.terms),
  };
}

export type PerkDraftProblem =
  | "partnerName"
  | "percent"
  | "amount"
  | "item"
  | "quantities"
  | "benefitText"
  | "code"
  | "partnerUrl"
  | "linkUrl"
  | "dates"
  | "windows"
  | "packages"
  | "groups"
  | "branches"
  | "maxClaims"
  | "perMember"
  | "period"
  | "minSpend"
  | "maxDiscount"
  | "tenure";

const positiveInteger = (value: number | null) => value !== null && Number.isInteger(value) && value > 0;
const inRange = (value: number | null, max: number) => positiveInteger(value) && value! <= max;

/** What the form must fix before saving; the API checks the same (`Benefit`, `Rules`, the method strategies). */
export function perkDraftProblems(draft: PerkDraft): PerkDraftProblem[] {
  const problems: PerkDraftProblem[] = [];
  if (!draft.partner_name.trim()) problems.push("partnerName");
  if (draft.benefit_type === "percent" && !inRange(draft.percent, 100)) problems.push("percent");
  if (draft.benefit_type === "fixed_amount" && !inRange(draft.amount_cents, 10_000_000)) problems.push("amount");
  if (draft.benefit_type === "free_item" && !draft.item?.trim()) problems.push("item");
  if (draft.benefit_type === "buy_x_get_y" && !(inRange(draft.buy_quantity, 100) && inRange(draft.get_quantity, 100))) problems.push("quantities");
  if (draft.benefit_type === "free_text" && !draft.text?.trim()) problems.push("benefitText");
  if (methodNeedsCode(draft.redemption_method, draft.link_url) && !PERK_CODE_PATTERN.test(normalizePerkCode(draft.shared_code ?? ""))) problems.push("code");
  const site = draft.partner_url?.trim() ?? "";
  if (site && !/^https?:\/\/\S+$/i.test(site)) problems.push("partnerUrl");
  if (draft.redemption_method === "partner_link" && !/^https:\/\/\S+$/i.test(draft.link_url?.trim() ?? "")) problems.push("linkUrl");
  if (draft.valid_from && draft.valid_until && draft.valid_until < draft.valid_from) problems.push("dates");
  if (draft.windows.some((window) => window.weekdays.length === 0 || !window.from || !window.until || window.until <= window.from)) problems.push("windows");
  if (draft.audience === "packages" && draft.package_ids.length === 0) problems.push("packages");
  if (draft.groups_only && draft.group_ids.length === 0) problems.push("groups");
  if (!draft.all_locations && draft.location_ids.length === 0) problems.push("branches");
  if (draft.max_claims !== null && !positiveInteger(draft.max_claims)) problems.push("maxClaims");
  if (!inRange(draft.max_per_member, 1000)) problems.push("perMember");
  if (draft.period && !positiveInteger(draft.max_per_period) && !positiveInteger(draft.max_per_member_per_period)) problems.push("period");
  if (draft.min_spend_cents !== null && !positiveInteger(draft.min_spend_cents)) problems.push("minSpend");
  if (draft.benefit_type === "percent" && draft.max_discount_cents !== null && !positiveInteger(draft.max_discount_cents)) problems.push("maxDiscount");
  if (draft.min_tenure_days !== null && !positiveInteger(draft.min_tenure_days)) problems.push("tenure");
  return problems;
}

/**
 * Publishing: a demo business may draft but not go live (ADR-184), and a
 * code pool needs a free code (`freeCodes`: the pool's free codes plus what
 * the form is about to add).
 */
export function canPublishPerk(draft: PerkDraft, activation: string | null | undefined, freeCodes = 0) {
  if (activation === "demo" || perkDraftProblems(draft).length > 0) return false;
  return draft.redemption_method !== "code_pool" || freeCodes > 0;
}

/** The collapsed «Περισσότεροι όροι» sections and whether each holds anything. */
export type RuleSection = "limits" | "when" | "who" | "where" | "terms";

export function ruleSectionsSet(draft: PerkDraft): Record<RuleSection, boolean> {
  return {
    limits: draft.max_claims !== null || draft.max_per_member !== 1 || draft.period !== null || draft.min_spend_cents !== null || draft.max_discount_cents !== null,
    when: draft.windows.length > 0,
    who: draft.audience === "packages" || draft.groups_only || !draft.all_locations || draft.min_tenure_days !== null,
    where: draft.channel !== null || Boolean(draft.partner_address?.trim()),
    terms: Boolean(draft.terms?.trim() || draft.stacking?.trim() || draft.instructions?.trim()),
  };
}

export const MAX_CODES_PER_UPLOAD = 5000;

/**
 * Reads the partner's codes from pasted text or a CSV/TXT file: one per
 * line, or separated by commas, semicolons or tabs; a first-line header such
 * as «code» is skipped. Repeats count once; malformed ones are reported.
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
