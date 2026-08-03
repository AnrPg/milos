type LinkableNotification = {
  type: string;
  payload: Record<string, unknown>;
};

function payloadUrl(notification: LinkableNotification) {
  return typeof notification.payload.url === "string" ? notification.payload.url : null;
}

export function notificationTargetUrl(
  notification: LinkableNotification,
  role: string | null | undefined,
) {
  const rawUrl = payloadUrl(notification);
  const isAdmin = role === "admin" || role === "coach";

  if (
    notification.type === "chat_message" &&
    typeof notification.payload.thread_id === "string"
  ) {
    return `/account/activity/chats?thread=${encodeURIComponent(notification.payload.thread_id)}`;
  }

  if (!rawUrl || !rawUrl.startsWith("/")) return null;
  if (!isAdmin) return rawUrl;

  const parsed = new URL(rawUrl, "http://milos.local");
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

  return rawUrl;
}
