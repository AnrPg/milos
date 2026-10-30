/**
 * The four Partners verification notifications (ADR-280 §1): what they say
 * and where they lead. A sponsor is asked to vouch (`partner_vouch_request`),
 * a candidate got a vouch (`partner_vouched`), the Palee check was decided or
 * its selfie expired (`partner_verification_decided`, `outcome` approved |
 * rejected | expired), and a sponsor's pause after someone they vouched for
 * was suspended (`partner_sponsor_penalty`, never naming that person).
 */
export const VERIFY_NOTICES = [
  "partner_vouch_request",
  "partner_vouched",
  "partner_verification_decided",
  "partner_sponsor_penalty",
] as const;

type Payload = Record<string, unknown>;
type Translate = (key: string, values?: Record<string, string>) => string;

const text = (payload: Payload, key: string) => (typeof payload[key] === "string" ? (payload[key] as string) : "");

/** A calendar date (YYYY-MM-DD) as a Date at noon UTC, so no time zone moves it a day. */
export function dateAtNoon(isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return new Date(Date.UTC(year, (month || 1) - 1, day || 1, 12));
}

export function isVerifyNotice(type: string) {
  return (VERIFY_NOTICES as readonly string[]).includes(type);
}

function outcome(payload: Payload) {
  const value = text(payload, "outcome");
  return value === "approved" || value === "rejected" || value === "expired" ? value : "rejected";
}

export function verifyNotificationUrl(type: string, payload: Payload): string | null {
  switch (type) {
    case "partner_vouch_request":
    case "partner_sponsor_penalty":
      return "/partners/vouch-requests";
    case "partner_vouched":
      return "/partners/verify";
    case "partner_verification_decided":
      return outcome(payload) === "approved" ? "/partners" : "/partners/verify";
    default:
      return null;
  }
}

/** Keys under the PartnerVerify namespace: notif.<type>[_<outcome>]_<part>. */
export function verifyNotificationText(
  type: string,
  payload: Payload,
  part: "title" | "body",
  t: Translate,
  formatDate: (isoDate: string) => string = (isoDate) => isoDate,
): string | null {
  if (!isVerifyNotice(type)) return null;
  switch (type) {
    case "partner_vouch_request":
      return t(`notif.vouchRequest_${part}`, { name: text(payload, "candidate_nickname") || t("someone") });
    case "partner_vouched":
      return t(`notif.vouched_${part}`, { name: text(payload, "sponsor_nickname") || t("someone") });
    case "partner_verification_decided": {
      const result = outcome(payload);
      const reason = text(payload, "reason");
      if (part === "body" && result === "rejected" && reason) return t("notif.decided_rejected_reason", { reason });
      return t(`notif.decided_${result}_${part}`);
    }
    default: {
      const until = text(payload, "until");
      if (part === "body" && until) return t("notif.penalty_body", { date: formatDate(until) });
      return t(part === "title" ? "notif.penalty_title" : "notif.penalty_bodyNoDate");
    }
  }
}
