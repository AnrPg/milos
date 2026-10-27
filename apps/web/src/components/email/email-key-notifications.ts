type Translate = (key: string, values?: Record<string, string>) => string;

/**
 * ADR-212: the bell's text for the vendors' "the SMTP key expires" alert.
 * `null` for any other notification.
 */
export function emailKeyNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: Translate,
) {
  if (type !== "email_key_expiring") return null;
  const days = typeof payload.days_left === "number" || typeof payload.days_left === "string" ? Number(payload.days_left) : NaN;
  const expired = Number.isFinite(days) && days < 0;
  if (part === "title") return t(expired ? "notifKeyExpiredTitle" : "notifKeyExpiringTitle");
  const date = typeof payload.expires_on === "string" && payload.expires_on ? payload.expires_on : "—";
  if (expired) return t("notifKeyExpiredBody", { date });
  return t("notifKeyExpiringBody", { days: Number.isFinite(days) ? String(days) : "—", date });
}
