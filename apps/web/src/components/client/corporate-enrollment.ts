import { ApiError } from "@/api/client";
import { CORPORATE_EMAIL_UNVERIFIED_CODE, type CorporateEnrollmentOffer } from "@/api/my-finance";

/** Query parameter of the enrollment link admins send to employees (ADR-098). */
export const COMPANY_CODE_PARAM = "company_code";

/** The enrollment code from a link's query string, if it carries one. */
export function companyCodeFromSearch(search: string): string | null {
  const code = new URLSearchParams(search).get(COMPANY_CODE_PARAM)?.trim();
  return code ? code.toUpperCase() : null;
}

/** The link an admin shares with a corporate client's employees. */
export function companyEnrollmentLink(origin: string, code: string): string {
  return `${origin}/account/billing?${COMPANY_CODE_PARAM}=${encodeURIComponent(code)}`;
}

/**
 * ADR-205: whether the card asks the member to confirm their email before
 * joining: the email-domain offer says so, or joining by domain was refused
 * for it. An enrollment link's code never needs it.
 */
export function needsEmailConfirmation(
  linkCode: string | null,
  offer: CorporateEnrollmentOffer | null,
  enrollError: unknown,
): boolean {
  if (linkCode) return false;
  if (enrollError instanceof ApiError && enrollError.payload.code === CORPORATE_EMAIL_UNVERIFIED_CODE) return true;
  return Boolean(offer?.needs_verification);
}
