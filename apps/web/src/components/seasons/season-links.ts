/**
 * The bell's words and links for ADR-167's season notices. A request reaches
 * the gym's staff and opens the builder on that season; confirm, decline and
 * cancel reach the member and open the season in Box.
 */
export const SEASON_NOTIFICATION_TYPES = [
  "season_requested",
  "season_confirmed",
  "season_declined",
  "season_cancelled",
] as const;

export type SeasonNotificationType = (typeof SEASON_NOTIFICATION_TYPES)[number];

export function isSeasonNotification(type: string): type is SeasonNotificationType {
  return (SEASON_NOTIFICATION_TYPES as readonly string[]).includes(type);
}

const text = (payload: Record<string, unknown>, key: string) =>
  typeof payload[key] === "string" ? (payload[key] as string).trim() : "";

export function seasonNotificationUrl(type: string, payload: Record<string, unknown>): string | null {
  if (!isSeasonNotification(type)) return null;
  const id = text(payload, "season_id");
  const season = id ? `season=${encodeURIComponent(id)}` : "";
  if (type === "season_requested") return `/admin/finance?tab=seasons${season ? `&${season}` : ""}`;
  return season ? `/box?${season}` : "/box";
}

export function seasonNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: (key: string, values?: Record<string, string | number>) => string,
): string | null {
  if (!isSeasonNotification(type)) return null;
  const values = {
    season: text(payload, "season_title") || t("notif.aSeason"),
    person: text(payload, "person_nickname") || t("notif.someone"),
    box: text(payload, "box_name") || t("notif.theBox"),
  };
  if (type === "season_requested") {
    const waitlisted = text(payload, "enrollment_status") === "waitlisted";
    return part === "title"
      ? t("notif.season_requested.title", values)
      : t(waitlisted ? "notif.season_requested.bodyWaitlist" : "notif.season_requested.body", values);
  }
  const line = t(`notif.${type}.${part}`, values);
  const reason = text(payload, "reason");
  return part === "body" && type === "season_declined" && reason ? `${line} «${reason}»` : line;
}
