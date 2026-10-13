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
