/**
 * Where ADR-160's notifications open on the web. The API stores its own
 * paths (`/me/buddies`, `/me/support-requests/:id`, `/me/buddies/:id/messages`,
 * `/admin/users/:id`); the web screens are `/me/buddy`, its support and chat
 * screens, and the coach's client page on the Ευεξία tab.
 */
export const BUDDY_NOTIFICATION_TYPES = [
  "buddy_invite",
  "buddy_accepted",
  "support_request",
  "support_reply",
  "support_no_reply_nudge",
  "buddy_weekly_summary",
  "buddy_message",
  "coach_wellness_summary",
] as const;

export type BuddyNotificationType = (typeof BUDDY_NOTIFICATION_TYPES)[number];

export function isBuddyNotification(type: string): type is BuddyNotificationType {
  return (BUDDY_NOTIFICATION_TYPES as readonly string[]).includes(type);
}

const text = (payload: Record<string, unknown>, key: string) => (typeof payload[key] === "string" ? (payload[key] as string) : "");
const enc = encodeURIComponent;

export function buddyNotificationUrl(type: string, payload: Record<string, unknown>): string | null {
  if (!isBuddyNotification(type)) return null;
  const requestId = text(payload, "request_id");
  const linkId = text(payload, "link_id");
  switch (type) {
    case "buddy_invite":
    case "buddy_accepted":
    case "buddy_weekly_summary":
      return "/me/buddy";
    case "support_request":
    case "support_no_reply_nudge":
      return requestId ? `/me/buddy/support/${enc(requestId)}` : "/me/buddy";
    case "support_reply":
      if (linkId) return `/me/buddy/${enc(linkId)}/chat`;
      return requestId ? `/me/buddy/support/${enc(requestId)}` : "/me/buddy";
    case "buddy_message":
      return linkId ? `/me/buddy/${enc(linkId)}/chat` : "/me/buddy";
    case "coach_wellness_summary": {
      const client = text(payload, "client_user_id");
      return client ? `/admin/users/${enc(client)}?tab=wellbeing#wellness_summary` : "/admin/users";
    }
  }
}

/**
 * The API's own paths for these screens, as redirects, so a push opened by
 * the service worker (which goes to the payload's URL) still lands right.
 */
export const BUDDY_REDIRECTS: ReadonlyArray<{ source: string; destination: string }> = [
  { source: "/me/buddies", destination: "/me/buddy" },
  { source: "/me/buddies/:id/messages", destination: "/me/buddy/:id/chat" },
  { source: "/me/support-requests/:id", destination: "/me/buddy/support/:id" },
  { source: "/buddy-invite/:token", destination: "/buddy/:token" },
  { source: "/journal/wellness", destination: "/journal/wellbeing" },
];

const number = (payload: Record<string, unknown>, key: string) => {
  const value = payload[key];
  return typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" && !Number.isNaN(Number(value)) ? Number(value) : 0;
};

/**
 * The bell's words for ADR-160's notices (Buddy.notif.<type>.title|body),
 * calm and short; a buddy message names who wrote, never what.
 */
export function buddyNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: (key: string, values?: Record<string, string | number>) => string,
): string | null {
  if (!isBuddyNotification(type)) return null;
  const name = text(payload, "nickname") || text(payload, "client_nickname") || t("someone");
  const values: Record<string, string | number> = {
    name,
    moments: number(payload, "hard_moments"),
    overcome: number(payload, "overcome"),
    requests: number(payload, "support_requests"),
    sleep: number(payload, "sleep_nights"),
    water: number(payload, "water_days"),
    meals: number(payload, "meal_days"),
  };
  if (part === "title") return t(["notif", type, "title"].join("."), values);
  if (type === "support_request") {
    const message = text(payload, "message");
    const body = t("notif.support_request.body", values);
    return message ? `«${message}» · ${body}` : body;
  }
  if (type === "support_reply") {
    const kind = text(payload, "kind");
    const own = text(payload, "text");
    if (kind === "text" && own) return own;
    const quick = kind === "walk" || kind === "call" ? kind : "here";
    const words = t(["reply", quick].join("."));
    return own ? `${words} ${own}` : words;
  }
  return t(["notif", type, "body"].join("."), values);
}
