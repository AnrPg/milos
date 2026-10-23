type Translate = (key: string, values?: Record<string, string>) => string;

/**
 * ADR-187: the bell's text for a password reset request (handlers) and for
 * the reset itself (the person). `null` for any other notification.
 */
export function passwordResetNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: Translate,
) {
  const suffix = part === "title" ? "Title" : "Body";
  if (type === "password_reset_completed") return t(`notifCompleted${suffix}`);
  if (type !== "password_reset_requested") return null;
  if (part === "title") return t("notifRequestedTitle");
  const text = (key: string) => (typeof payload[key] === "string" ? (payload[key] as string).trim() : "");
  const handle = text("person_handle").replace(/^@/, "");
  return t("notifRequestedBody", { name: text("person_name") || (handle ? `@${handle}` : "—"), handle: handle || "—" });
}
