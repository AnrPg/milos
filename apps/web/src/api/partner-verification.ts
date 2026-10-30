import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Partners verification (ADR-280 §5): the person's own path
 * (`/me/partners/verification*`: consent, sponsors from one's Φιλαράκια or a
 * single-use link, mobile number and code, the selfie for the Palee check)
 * and the sponsor's side (`vouch-requests`, `vouch-links`, `vouching`).
 */
export type VerificationOverview = components["schemas"]["PartnerVerificationOverview"];
export type VerificationRequest = NonNullable<VerificationOverview["request"]>;
export type VerificationEligibility = VerificationOverview["eligibility"];
export type VerificationLimits = VerificationOverview["limits"];
export type VerificationStep = NonNullable<VerificationEligibility["next_step"]>;
export type VerificationSponsor = VerificationRequest["sponsors"][number];
export type SponsorCandidates = components["schemas"]["PartnerSponsorCandidates"];
export type SponsorCandidate = components["schemas"]["PartnerSponsorCandidate"];
export type SponsorshipStatus = components["schemas"]["PartnerSponsorship"]["status"];
export type SponsorshipResponse = components["schemas"]["PartnerSponsorshipResponse"];
export type SponsorLink = components["schemas"]["PartnerSponsorLink"];
export type PhoneSent = components["schemas"]["PartnerPhoneSent"];
export type SelfieUpload = components["schemas"]["PartnerSelfieUpload"];
export type SelfieContentType = components["schemas"]["PartnerSelfieUploadRequest"]["content_type"];
export type VouchRequests = components["schemas"]["PartnerVouchRequests"];
export type VouchRequest = components["schemas"]["PartnerVouchRequest"];
export type Vouching = components["schemas"]["PartnerVouching"];
export type VouchDecision = components["schemas"]["PartnerVouchDecision"]["decision"];
export type VouchResult = components["schemas"]["PartnerVouchResult"];
export type VouchLinkInspection = components["schemas"]["PartnerVouchLinkInspection"];
export type VerificationPerson = components["schemas"]["PartnerVerificationPerson"];

export const VERIFICATION_KEY = ["my", "partners", "verification"] as const;
export const SPONSOR_CANDIDATES_KEY = [...VERIFICATION_KEY, "sponsor-candidates"] as const;
export const VOUCH_REQUESTS_KEY = ["my", "partners", "vouch-requests"] as const;
export const VOUCHING_KEY = ["my", "partners", "vouching"] as const;

const BASE = "/me/partners/verification";

export function fetchVerification(token: string) {
  return apiRequest<VerificationOverview>(BASE, { token, scope: "account" });
}

export function giveConsent(token: string) {
  return apiRequest<VerificationOverview>(`${BASE}/consent`, { method: "POST", token, scope: "account" });
}

export function fetchSponsorCandidates(token: string) {
  return apiRequest<SponsorCandidates>(`${BASE}/sponsor-candidates`, { token, scope: "account" });
}

export function askSponsor(token: string, sponsorId: string) {
  return apiRequest<SponsorshipResponse>(`${BASE}/sponsors`, {
    method: "POST",
    token,
    scope: "account",
    body: { sponsor_id: sponsorId },
  });
}

/** Withdraws an unanswered request; takes the sponsor's person id. */
export function cancelSponsor(token: string, sponsorId: string) {
  return apiRequest<SponsorshipResponse>(`${BASE}/sponsors/${encodeURIComponent(sponsorId)}`, {
    method: "DELETE",
    token,
    scope: "account",
  });
}

export function createSponsorLink(token: string) {
  return apiRequest<SponsorLink>(`${BASE}/link`, { method: "POST", token, scope: "account" });
}

export function sendPhoneCode(token: string, phone: string) {
  return apiRequest<PhoneSent>(`${BASE}/phone`, { method: "POST", token, scope: "account", body: { phone } });
}

export function confirmPhone(token: string, code: string) {
  return apiRequest<VerificationOverview>(`${BASE}/phone/confirm`, { method: "POST", token, scope: "account", body: { code } });
}

export function selfieUploadUrl(token: string, contentType: SelfieContentType) {
  return apiRequest<SelfieUpload>(`${BASE}/selfie/upload-url`, {
    method: "POST",
    token,
    scope: "account",
    body: { content_type: contentType },
  });
}

export function submitVerification(token: string, fileKey: string) {
  return apiRequest<VerificationOverview>(`${BASE}/submit`, { method: "POST", token, scope: "account", body: { file_key: fileKey } });
}

/** Withdraws the request: phone, selfie, open sponsor requests and links are deleted. */
export function withdrawVerification(token: string) {
  return apiRequest<VerificationOverview>(BASE, { method: "DELETE", token, scope: "account" });
}

// ------------------------------------------------------------ the sponsor

export function fetchVouchRequests(token: string) {
  return apiRequest<VouchRequests>("/me/partners/vouch-requests", { token, scope: "account" });
}

export function decideVouch(token: string, id: string, decision: VouchDecision) {
  return apiRequest<VouchResult>(`/me/partners/vouch-requests/${encodeURIComponent(id)}`, {
    method: "POST",
    token,
    scope: "account",
    body: { decision },
  });
}

export function inspectVouchLink(token: string, linkToken: string) {
  return apiRequest<VouchLinkInspection>("/me/partners/vouch-links/inspect", {
    method: "POST",
    token,
    scope: "account",
    body: { token: linkToken },
  });
}

export function vouchByLink(token: string, linkToken: string) {
  return apiRequest<VouchResult>("/me/partners/vouch-links/vouch", {
    method: "POST",
    token,
    scope: "account",
    body: { token: linkToken },
  });
}

export function fetchVouching(token: string) {
  return apiRequest<Vouching>("/me/partners/vouching", { token, scope: "account" });
}
