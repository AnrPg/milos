import { buddyNotificationUrl } from "@/components/buddy/buddy-links";
import { conversationNotificationUrl } from "@/components/conversations/conversation-links";
import { seasonNotificationUrl } from "@/components/seasons/season-links";
import { shopNotificationUrl } from "@/components/shop/shop-links";
import { socialNotificationUrl } from "@/components/social/social-model";
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
  // ADR-185: co-host requests and answers open the organiser console.
  const consoleUrl = notification.payload.url;
  if (
    (notification.type === "community_event_cohost_request" || notification.type === "community_event_cohost_answered") &&
    typeof consoleUrl === "string" &&
    consoleUrl.startsWith("/events/hosting")
  ) {
    return consoleUrl;
  }
  if (
    notification.type.startsWith("community_event_") &&
    notification.type !== "community_event_trial_offer" &&
    typeof eventId === "string" &&
    eventId
  ) {
    return `/events/${encodeURIComponent(eventId)}`;
  }
  // ADR-176: a class without its WOD opens it in the staff schedule.
  if (notification.type === "class_workout_missing" && typeof slotId === "string" && slotId) {
    return `/admin/schedule?open_slot=${encodeURIComponent(slotId)}`;
  }
  // ADR-187: a password reset request opens that request; the reset itself opens Settings.
  if (notification.type === "password_reset_requested") {
    const requestId = notification.payload.request_id;
    return typeof requestId === "string" && requestId
      ? `/password-resets?request=${encodeURIComponent(requestId)}`
      : "/password-resets";
  }
  if (notification.type === "password_reset_completed") return "/me/settings#security";
  // ADR-184 follow-up: the idle-demo reminder opens the demo's console (opening it keeps it).
  if (notification.type === "business_demo_idle") return "/admin";
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
    // ADR-226: my weekly goal lives in Εγώ › Ρυθμίσεις.
    case "training_goal_updated":
      return "/me/settings#training-schedule";
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
  if (notification.type === "booking_waitlist_promoted" || notification.type === "class_cancelled") return "/box/schedule";
  if (notification.type === "package_expiring") return "/me/payments";
  // ADR-156: the member's referral notices open their invites, staff's the queue.
  if (notification.type === "referral_progress" || notification.type === "referral_reward") return "/me/referrals?tab=invites";
  if (notification.type === "referral_review") return "/admin/finance?tab=referrals";
  return null;
}

function localTarget(rawUrl: string) {
  const origin = "http://palee.local";

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
  // ADR-193: a person's message opens the conversation, a request the requests.
  const conversation = conversationNotificationUrl(notification.type, notification.payload);
  if (conversation) return conversation;
  // ADR-167: a season request opens the builder on it, an answer the season in Box.
  const season = seasonNotificationUrl(notification.type, notification.payload);
  if (season) return season;
  // ADR-190: a shop order notice opens the order in Box › Κατάστημα.
  const shop = shopNotificationUrl(notification.type, notification.payload);
  if (shop) return shop;
  // ADR-193 §2: a new follower of a public account opens their profile.
  const social = socialNotificationUrl(notification.type, notification.payload);
  if (social) return social;

  const rawUrl = preferredUrl(notification) ?? payloadUrl(notification) ?? fallbackUrl(notification);
  const isAdmin = isStaffRole(role);

  if (
    notification.type === "chat_message" &&
    typeof notification.payload.thread_id === "string"
  ) {
    return `/messages?thread=${encodeURIComponent(notification.payload.thread_id)}`;
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
