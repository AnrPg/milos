import type { PasswordResetRequest } from "@/api/password-resets";

type Translate = (key: string, values?: Record<string, string | number>) => string;

/** Who the request came through: the boxes by name, "Your client", "Palee". */
export function sourceLabels(request: Pick<PasswordResetRequest, "sources" | "organizations">, t: Translate) {
  const labels: string[] = [];
  if (request.sources.includes("box")) labels.push(...request.organizations);
  if (request.sources.includes("coach")) labels.push(t("sourceCoach"));
  if (request.sources.includes("vendor")) labels.push(t("sourceVendor"));
  return Array.from(new Set(labels.filter(Boolean)));
}

export function claimerName(request: Pick<PasswordResetRequest, "claimed_by">, t: Translate) {
  const claimer = request.claimed_by;
  return claimer?.display_name || (claimer?.handle ? `@${claimer.handle}` : t("someone"));
}

/** The vendor may take over a request someone else holds. */
export function canTakeOver(request: Pick<PasswordResetRequest, "sources">) {
  return request.sources.includes("vendor");
}
