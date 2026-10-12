type LinkableNotification = {
  type: string;
  payload: Record<string, unknown>;
};

function payloadUrl(notification: LinkableNotification) {
  return typeof notification.payload.url === "string" ? notification.payload.url : null;
}

// ADR-097: a promoted waitlist place opens its class; an expiring package
// opens Billing even when the payload carries no explicit URL.
function preferredUrl(notification: LinkableNotification) {
  const slotId = notification.payload.scheduled_class_id;
  if (notification.type === "booking_waitlist_promoted" && typeof slotId === "string" && slotId) {
    return `/schedule?open_slot=${encodeURIComponent(slotId)}`;
  }
  return null;
}

function fallbackUrl(notification: LinkableNotification) {
  if (notification.type === "booking_waitlist_promoted") return "/schedule";
  if (notification.type === "package_expiring") return "/account/billing";
  return null;
}

function localTarget(rawUrl: string) {
  const origin = "http://milos.local";

  try {
    const parsed = new URL(rawUrl, origin);

    if (parsed.origin !== origin || !parsed.pathname.startsWith("/")) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function notificationTargetUrl(
  notification: LinkableNotification,
  role: string | null | undefined,
) {
  const rawUrl = preferredUrl(notification) ?? payloadUrl(notification) ?? fallbackUrl(notification);
  const isAdmin = role === "admin" || role === "coach";

  if (
    notification.type === "chat_message" &&
    typeof notification.payload.thread_id === "string"
  ) {
    return `/account/activity/chats?thread=${encodeURIComponent(notification.payload.thread_id)}`;
  }

  if (!rawUrl) return null;
  const parsed = localTarget(rawUrl);
  if (!parsed) return null;

  const localUrl = `${parsed.pathname}${parsed.search}${parsed.hash}`;
  if (!isAdmin) return localUrl;

  const params = parsed.searchParams;

  if (
    parsed.pathname === "/my-workouts" ||
    parsed.pathname === "/admin/coaching-assignments"
  ) {
    const assignmentId = params.get("open_assignment") ?? params.get("open");
    const nextParams = new URLSearchParams();

    if (assignmentId) nextParams.set("open_assignment", assignmentId);
    const date = params.get("date");
    if (date) nextParams.set("date", date);

    const query = nextParams.toString();
    return `/admin/coaching-assignments${query ? `?${query}` : ""}`;
  }

  if (
    parsed.pathname === "/schedule" ||
    parsed.pathname === "/admin/schedule" ||
    parsed.pathname === "/admin/class-schedule"
  ) {
    const slotId = params.get("open_slot") ?? params.get("open");
    const nextParams = new URLSearchParams(params);
    nextParams.delete("open");
    if (slotId) nextParams.set("open_slot", slotId);

    const query = nextParams.toString();
    return `/admin/class-schedule${query ? `?${query}` : ""}`;
  }

  return localUrl;
}
