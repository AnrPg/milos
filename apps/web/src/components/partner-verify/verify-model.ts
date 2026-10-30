import { ApiError } from "@/api/client";
import type {
  SelfieContentType,
  SponsorCandidate,
  VerificationOverview,
  VerificationRequest,
  VerificationStep,
} from "@/api/partner-verification";

/**
 * The verification page as a pure model (ADR-280 §2): which screen the
 * person sees, the four steps of the sponsor path and what each one may do.
 * After consent the sponsors and the mobile number can be done in any order
 * (the API allows both); the selfie opens only when both are done, since
 * the API refuses to submit without them.
 */
export const STEPS: VerificationStep[] = ["consent", "sponsors", "phone", "selfie"];

export type StepState = "done" | "open" | "locked";
export type StepItem = { key: VerificationStep; state: StepState; current: boolean };

export type VerifyView =
  | { kind: "verified"; method: "membership" | "sponsors" | null }
  | { kind: "suspended" }
  | { kind: "in_review"; request: VerificationRequest | null }
  | { kind: "rejected"; reason: string | null }
  | { kind: "steps"; steps: StepItem[]; request: VerificationRequest | null; selfieExpired: boolean };

export function verifyView(overview: VerificationOverview): VerifyView {
  const { eligibility, request } = overview;
  switch (eligibility.status) {
    case "verified":
      return { kind: "verified", method: eligibility.method };
    case "suspended":
      return { kind: "suspended" };
    case "in_review":
      return { kind: "in_review", request };
    case "rejected":
      return { kind: "rejected", reason: request?.decision_reason ?? null };
    default:
      return {
        kind: "steps",
        steps: stepItems(request, eligibility.next_step ?? "consent"),
        request,
        selfieExpired: request?.status === "expired",
      };
  }
}

export function stepItems(request: VerificationRequest | null, next: VerificationStep): StepItem[] {
  const consented = Boolean(request?.consent_at);
  const sponsorsDone = Boolean(request && request.vouches >= request.sponsors_required);
  const phoneDone = Boolean(request?.phone_verified);
  const state: Record<VerificationStep, StepState> = {
    consent: consented ? "done" : "open",
    sponsors: !consented ? "locked" : sponsorsDone ? "done" : "open",
    phone: !consented ? "locked" : phoneDone ? "done" : "open",
    selfie: consented && sponsorsDone && phoneDone ? "open" : "locked",
  };
  return STEPS.map((key) => ({ key, state: state[key], current: key === next }));
}

/** Whether a request may still be withdrawn (open: collecting, in review or expired). */
export function canWithdraw(request: VerificationRequest | null) {
  return Boolean(request && ["collecting", "in_review", "expired"].includes(request.status));
}

// ------------------------------------------------------------ sponsors

export type CandidateAction = "ask" | "cancel" | "none";

/**
 * What a Buddy's row offers: ask when they may vouch and have not been asked
 * (or the request was cancelled), cancel while unanswered, nothing once they
 * answered or when they cannot vouch. A full set of vouches asks no more.
 */
export function candidateAction(candidate: SponsorCandidate, enough: boolean): CandidateAction {
  const status = candidate.sponsorship?.status;
  if (status === "requested") return "cancel";
  if (status === "vouched" || status === "declined") return "none";
  if (!candidate.eligible || enough) return "none";
  return "ask";
}

/** Eligible Buddies first, then by whether they were asked, then by name. */
export function sortCandidates(candidates: SponsorCandidate[]) {
  const rank = (candidate: SponsorCandidate) => {
    const status = candidate.sponsorship?.status;
    if (status === "vouched") return 0;
    if (status === "requested") return 1;
    if (candidate.eligible && status !== "declined") return 2;
    if (status === "declined") return 3;
    return 4;
  };
  return [...candidates].sort(
    (a, b) => rank(a) - rank(b) || (a.person.nickname ?? "").localeCompare(b.person.nickname ?? ""),
  );
}

// ------------------------------------------------------------ link countdown

/** Whole seconds left until `expiresAt`, never below zero. */
export function secondsLeft(expiresAt: string, now: number) {
  return Math.max(0, Math.ceil((Date.parse(expiresAt) - now) / 1000));
}

/** «9:05» for 545 seconds. */
export function formatCountdown(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
}

// ------------------------------------------------------------ phone and code

/** Digits only, at most 6: what the code field keeps. */
export function cleanCode(value: string) {
  return value.replace(/\D/g, "").slice(0, 6);
}

/** A number worth sending: 8 to 15 digits after an optional +. The API normalises it. */
export function plausiblePhone(value: string) {
  const digits = value.replace(/[\s().-]/g, "");
  return /^\+?\d{8,15}$/.test(digits);
}

// ------------------------------------------------------------ selfie

const EXTENSION_TYPES: Record<string, SelfieContentType> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heic",
};

/** The content type the API accepts for a picked file, or null. */
export function selfieContentType(file: { type: string; name: string }, accepted: string[]): SelfieContentType | null {
  const declared = file.type === "image/heif" ? "image/heic" : file.type;
  if (declared && accepted.includes(declared)) return declared as SelfieContentType;
  const extension = file.name.split(".").pop()?.toLowerCase() ?? "";
  const guessed = EXTENSION_TYPES[extension];
  return guessed && accepted.includes(guessed) ? guessed : null;
}

export type SelfieProblem = "type" | "size" | null;

export function selfieProblem(file: { type: string; name: string; size: number }, accepted: string[], maxBytes: number): SelfieProblem {
  if (!selfieContentType(file, accepted)) return "type";
  if (file.size > maxBytes) return "size";
  return null;
}

// ------------------------------------------------------------ errors

/** The codes the verification screens word themselves (PartnerVerify.error.<code>). */
export const VERIFY_ERROR_CODES = [
  "partner_verification_required",
  "partner_suspended",
  "partner_already_verified",
  "partner_verification_in_review",
  "partner_verification_request_open",
  "partner_consent_required",
  "partner_sponsor_not_eligible",
  "partner_sponsor_quota",
  "partner_sponsor_penalty",
  "partner_sponsor_declined",
  "partner_sponsor_already_asked",
  "partner_vouch_request_closed",
  "partner_link_expired",
  "partner_phone_invalid",
  "partner_phone_taken",
  "partner_phone_rate_limited",
  "partner_code_invalid",
  "partner_code_expired",
  "partner_selfie_missing",
  "partner_selfie_invalid",
  "partner_verification_incomplete",
  "partner_verification_closed",
  "partner_decision_reason_required",
  "partner_decision_reason_too_long",
  "sms_unavailable",
] as const;

export type VerifyErrorCode = (typeof VERIFY_ERROR_CODES)[number];

/** Where an error shows: under a field of the form, or for the whole step. */
export type VerifyErrorField = "phone" | "code" | "selfie" | "reason" | "form";

const FIELD_OF: Partial<Record<VerifyErrorCode, VerifyErrorField>> = {
  partner_phone_invalid: "phone",
  partner_phone_taken: "phone",
  partner_phone_rate_limited: "phone",
  sms_unavailable: "phone",
  partner_code_invalid: "code",
  partner_code_expired: "code",
  partner_selfie_missing: "selfie",
  partner_selfie_invalid: "selfie",
  partner_decision_reason_required: "reason",
  partner_decision_reason_too_long: "reason",
};

export function verifyErrorCode(error: unknown): VerifyErrorCode | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return (VERIFY_ERROR_CODES as readonly string[]).includes(error.payload.code) ? (error.payload.code as VerifyErrorCode) : null;
}

export function verifyErrorField(error: unknown): VerifyErrorField {
  const code = verifyErrorCode(error);
  return (code && FIELD_OF[code]) ?? "form";
}

/** The message key under PartnerVerify for an error, or null for the shared wording. */
export function verifyErrorKey(error: unknown): string | null {
  const code = verifyErrorCode(error);
  return code ? `error.${code}` : null;
}

/** The error for one field: only when it belongs there. */
export function errorFor(error: unknown, field: VerifyErrorField) {
  return error && verifyErrorField(error) === field ? error : null;
}
