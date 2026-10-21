import { buddyNotificationUrl } from "@/components/buddy/buddy-links";
import { seasonNotificationUrl } from "@/components/seasons/season-links";
import { currentMemberPath } from "@/lib/member-routes";

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
    return `/box/schedule?open_slot=${encodeURIComponent(slotId)}`;
  }
  // ADR-153: event notifications open the event page; the trial offer keeps
  // its own link to the box's trial sheet.
  const eventId = notification.payload.event_id;
  if (
    notification.type.startsWith("community_event_") &&
    notification.type !== "community_event_trial_offer" &&
    typeof eventId === "string" &&
    eventId
  ) {
    return `/events/${encodeURIComponent(eventId)}`;
  }
  // ADR-155: a visitor at the door opens the desk on that visitor.
  if (notification.type === "check_in_visitor") {
    const scanId = notification.payload.scan_id;
    return typeof scanId === "string" && scanId ? `/admin/check-in?visitor=${encodeURIComponent(scanId)}#visitors` : "/admin/check-in#visitors";
  }
  // ADR-154: a saved Γύρω μου filter's alert opens Γύρω μου with that filter.
  const filterId = notification.payload.filter_id;
  if (notification.type === "around_new_matches") {
    return typeof filterId === "string" && filterId ? `/around?filter=${encodeURIComponent(filterId)}` : "/around";
  }
  return null;
}

const STAFF_ROLES = new Set(["admin", "coach", "owner", "front_desk", "accountant", "janitor"]);

function isStaffRole(role: string | null | undefined) {
  return Boolean(role && STAFF_ROLES.has(role));
}

// ADR-098: coaching and appointment notifications open the Phase C screens.
// The API stores generic URLs, so the web app picks the screen by type and by
// whether the reader is staff (appointment_cancelled reaches both sides).
function phaseCUrl(notification: LinkableNotification, role: string | null | undefined) {
  switch (notification.type) {
    case "form_review_submitted":
      return "/admin/coaching?tab=form-reviews";
    case "coaching_reply_overdue":
      return "/admin/coaching?tab=replies";
    case "form_review_completed":
    case "nutrition_plan_updated":
      return "/box/coach";
    case "appointment_booked":
    case "appointment_cancelled":
      return isStaffRole(role) ? "/admin/appointments" : "/box/appointments";
    // ADR-104: inventory alerts and the daily summary open the right tab.
    case "inventory_repair_needed":
      return "/admin/inventory?tab=machines";
    case "inventory_stock_low":
      return "/admin/inventory?tab=supplies";
    case "inventory_digest":
      return "/admin/inventory";
    default:
      return null;
  }
}

function fallbackUrl(notification: LinkableNotification) {
  // ADR-161: a Garmin sync error opens the devices page to reconnect.
  if (notification.type === "device_sync_error") return "/me/devices";
  if (notification.type === "booking_waitlist_promoted") return "/box/schedule";
  if (notification.type === "package_expiring") return "/me/payments";
  // ADR-156: the member's referral notices open their invites, staff's the queue.
  if (notification.type === "referral_progress" || notification.type === "referral_reward") return "/me/referrals?tab=invites";
  if (notification.type === "referral_review") return "/admin/finance?tab=referrals";
  return null;
}

function localTarget(rawUrl: string) {
  const origin = "http://milos.local";

  try {
    // Payloads stored before the redesign still name the old member pages.
    const parsed = new URL(rawUrl.startsWith("/") ? currentMemberPath(rawUrl) : rawUrl, origin);

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
  const phaseC = phaseCUrl(notification, role);
  if (phaseC) return phaseC;
  // ADR-160: buddy notices open the buddy screens, the coach's the client page.
  const buddy = buddyNotificationUrl(notification.type, notification.payload);
  if (buddy) return buddy;
  // ADR-167: a season request opens the builder on it, an answer the season in Box.
  const season = seasonNotificationUrl(notification.type, notification.payload);
  if (season) return season;

  const rawUrl = preferredUrl(notification) ?? payloadUrl(notification) ?? fallbackUrl(notification);
  const isAdmin = isStaffRole(role);

  if (
    notification.type === "chat_message" &&
    typeof notification.payload.thread_id === "string"
  ) {
    return `/me/activity/chats?thread=${encodeURIComponent(notification.payload.thread_id)}`;
  }

  if (!rawUrl) return null;
  const parsed = localTarget(rawUrl);
  if (!parsed) return null;

  const localUrl = `${parsed.pathname}${parsed.search}${parsed.hash}`;
  if (!isAdmin) return localUrl;

  const params = parsed.searchParams;

  if (
    parsed.pathname === "/box/workouts" ||
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
    parsed.pathname === "/box/schedule" ||
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
