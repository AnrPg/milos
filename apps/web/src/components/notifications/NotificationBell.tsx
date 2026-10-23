"use client";









import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

import {
  fetchNotifications,
  markNotificationClicked,
  markAllNotificationsRead,
  type NotificationsResponse,
  type NotificationRecord,
} from "@/api/notifications";
import { useSession } from "@/components/session-provider";
import { usePushNotifications } from "@/hooks/usePushNotifications";
import { subscribeToTopic } from "@/lib/realtime";
import { notificationTargetUrl } from "@/components/notifications/notification-links";
import { buddyNotificationText } from "@/components/buddy/buddy-links";
import { seasonNotificationText } from "@/components/seasons/season-links";
import { shopNotificationText } from "@/components/shop/shop-links";
import { passwordResetNotificationText } from "@/components/password-resets/reset-notifications";
import {
  notificationOrigin,
  type NotificationOrigin,
} from "@/components/notifications/notification-origin";
import { useOrganizationMemberships } from "@/lib/membership-role";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { FollowRequestsRow } from "@/components/social/FollowRequestsRow";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { NavIcon } from "@/components/nav/NavIcons";
import { Dialog } from "@/components/ui/Dialog";

function formatTimestamp(uiLocale: string, isoString: string) {
  return new Intl.DateTimeFormat(uiLocale, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(isoString));
}

function NotificationCard({
  notification,
  targetUrl,
  onClick,
  origin,
}: {
  notification: NotificationRecord;
  targetUrl: string | null;
  onClick: () => void;
  origin: NotificationOrigin | null;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const tTrials = useTranslations("Trials");
  const tClubs = useTranslations("Clubs");
  const tReferrals = useTranslations("Referrals");
  const tAround = useTranslations("Around");
  const tCheckIn = useTranslations("CheckIn");
  const tDevices = useTranslations("Devices");
  // ADR-161: Garmin stopped answering; the notice opens Συνδεδεμένες συσκευές.
  function deviceText(notification: NotificationRecord, part: "title" | "body") {
    if (notification.type !== "device_sync_error") return null;
    return tDevices(["notif", "sync_error", part].join("_"));
  }
  const tPartners = useTranslations("Partners");
  // ADR-169: a new training partner, and a message from one (who, never what).
  function partnerText(notification: NotificationRecord, part: "title" | "body") {
    if (notification.type !== "partner_match" && notification.type !== "partner_message") return null;
    const nickname = notification.payload.nickname;
    const name = typeof nickname === "string" && nickname ? nickname : tPartners("someone");
    return tPartners(["notif", notification.type, part].join("_"), { name });
  }
  const tResets = useTranslations("passwordResets");
  // ADR-187: a password reset request (handlers) and the reset itself (the person).
  function passwordResetText(notification: NotificationRecord, part: "title" | "body") {
    return passwordResetNotificationText(notification.type, notification.payload, part, (key, values) => tResets(key, values));
  }
  const tBuddy = useTranslations("Buddy");
  const tSeasons = useTranslations("Seasons");
  const tShop = useTranslations("Shop");
  // ADR-190: a shop order ready for pickup, its reminder, a cancellation, and back in stock.
  function shopText(notification: NotificationRecord, part: "title" | "body") {
    return shopNotificationText(notification.type, notification.payload, part, (key, values) => tShop(key, values));
  }
  // ADR-167: season requests (staff) and their answers (members).
  function seasonText(notification: NotificationRecord, part: "title" | "body") {
    return seasonNotificationText(notification.type, notification.payload, part, (key, values) => tSeasons(key, values));
  }
  // ADR-160: buddy invitations, requests, replies and the weekly counts.
  function buddyText(notification: NotificationRecord, part: "title" | "body") {
    return buddyNotificationText(notification.type, notification.payload, part, (key, values) => tBuddy(key, values));
  }
  // ADR-155: a visitor at the door names the person, the box and when, and whether trials are open.
  function checkInText(notification: NotificationRecord, part: "title" | "body") {
    if (notification.type !== "check_in_visitor") return null;
    if (part === "title") return tCheckIn("notifVisitorTitle");
    const text = (key: string) => (typeof notification.payload[key] === "string" ? (notification.payload[key] as string) : "");
    const values = { name: text("person_nickname") || tCheckIn("visitorUnnamed"), box: text("box_name"), when: text("scanned_when") };
    const trials = notification.payload.trial_available === true || notification.payload.trial_available === "true";
    return tCheckIn(trials ? "notifVisitorBodyTrials" : "notifVisitorBody", values);
  }
  // ADR-154: a saved Γύρω μου filter's daily alert names the filter and how many are new.
  function aroundText(notification: NotificationRecord, part: "title" | "body") {
    if (notification.type !== "around_new_matches") return null;
    if (part === "title") return tAround("notifTitle");
    const name = typeof notification.payload.filter_name === "string" ? notification.payload.filter_name : "";
    const count = Number(notification.payload.count ?? 0);
    return tAround("notifBody", { name, count: Number.isFinite(count) ? count : 0 });
  }
  // ADR-143: group, report and open-club notifications carry their names (events: ADR-153).
  function communityText(notification: NotificationRecord, part: "title" | "body") {
    if (!(COMMUNITY_NOTICES as readonly string[]).includes(notification.type)) return null;
    const text = (key: string) => (typeof notification.payload[key] === "string" ? (notification.payload[key] as string) : "");
    if (notification.type.startsWith("community_event_")) return eventText(notification.type, part, text);
    const reason = text("reason");
    const values = {
      person: text("person_nickname") || tTrials("someone"),
      group: text("group_name"),
      club: text("club_name"),
      reason: reason ? tClubs(`reason_${reason}`) : "",
    };
    return tClubs(["notif", notification.type.replace(/^community_/, ""), part].join("_"), values);
  }
  // ADR-153: event notifications carry the event's title and its time in the
  // box's zone; a cancel its reason, a move what changed, staff's message its text.
  function eventText(type: string, part: "title" | "body", text: (key: string) => string) {
    const notice = type.replace(/^community_/, "");
    const values = {
      event: text("event_title"),
      when: text("event_when"),
      person: text("person_nickname") || tTrials("someone"),
      box: text("box_name"),
      reason: text("reason"),
    };
    if (part === "title") return tClubs(["notif", notice, "title"].join("_"), values);
    if (notice === "event_message") return text("message");
    let variant = "body";
    if (notice === "event_cancelled" && values.reason) variant = "reason_body";
    // ADR-185: an answer to a co-host request reads by the answer.
    if (notice === "event_cohost_answered") {
      const answer = text("answer");
      variant = answer === "accepted" || answer === "declined" ? [answer, "body"].join("_") : "removed_body";
    }
    if (notice === "event_changed") {
      const changes = text("changes").split(",");
      variant = changes.includes("place") ? (changes.includes("time") ? "both_body" : "place_body") : "body";
    }
    return tClubs(["notif", notice, variant].join("_"), values);
  }
  // ADR-144: trial notifications carry the box, the class and its time.
  function trialText(notification: NotificationRecord, part: "title" | "body") {
    const text = (key: string) => (typeof notification.payload[key] === "string" ? (notification.payload[key] as string) : "");
    const type = notification.type.replace(/^trial_/, "") as TrialNotice;
    if (!TRIAL_NOTICES.includes(type)) return null;
    const values = {
      person: text("person_nickname") || tTrials("someone"),
      box: text("box_name"),
      class: text("class_name"),
      when: text("class_when"),
    };
    if (part === "title") return tTrials(TRIAL_NOTICE_KEYS[type][0], values);
    const body = tTrials(TRIAL_NOTICE_KEYS[type][1], values);
    const reason = type === "declined" ? text("decline_reason") : "";
    return reason ? `${body} ${reason}` : body;
  }

  // ADR-156: the inviter hears each step and the reward; staff a referral to approve.
  function referralText(notification: NotificationRecord, part: "title" | "body") {
    if (!notification.type.startsWith("referral_")) return null;
    const text = (key: string) => (typeof notification.payload[key] === "string" ? (notification.payload[key] as string) : "");
    const values = {
      person: text("person_nickname") || tTrials("someone"),
      referrer: text("referrer_nickname") || tTrials("someone"),
      box: text("box_name"),
    };
    if (notification.type === "referral_progress") {
      if (part === "title") return tReferrals("notif.progressTitle");
      const stage = ["event", "trial", "joined", "paid"].includes(text("stage")) ? text("stage") : "signed_up";
      return tReferrals(`notif.progress.${stage}`, values);
    }
    if (notification.type === "referral_reward") {
      if (part === "title") return tReferrals("notif.rewardTitle");
      const status = ["given", "rejected"].includes(text("reward_status")) ? text("reward_status") : "approved";
      return tReferrals(`notif.reward.${status}`, values);
    }
    if (notification.type === "referral_review") {
      return part === "title" ? tReferrals("notif.reviewTitle") : tReferrals("notif.reviewBody", values);
    }
    return null;
  }

  function notificationBody(notification: NotificationRecord) {
    const passwordReset = passwordResetText(notification, "body");
    if (passwordReset !== null) return passwordReset;
    const buddy = buddyText(notification, "body");
    if (buddy !== null) return buddy;
    const season = seasonText(notification, "body");
    if (season !== null) return season;
    const shop = shopText(notification, "body");
    if (shop !== null) return shop;
    const partner = partnerText(notification, "body");
    if (partner !== null) return partner;
    const device = deviceText(notification, "body");
    if (device !== null) return device;
    const checkIn = checkInText(notification, "body");
    if (checkIn !== null) return checkIn;
    const around = aroundText(notification, "body");
    if (around !== null) return around;
    const trial = trialText(notification, "body");
    if (trial !== null) return trial;
    const referral = referralText(notification, "body");
    if (referral !== null) return referral;
    const community = communityText(notification, "body");
    if (community !== null) return community;
    if (typeof notification.payload.body === "string") {
      return notification.payload.body;
    }
  
    if (notification.type === "workout_note") {
      const notePayload =
        typeof notification.payload.note === "object" && notification.payload.note !== null
          ? (notification.payload.note as Record<string, unknown>)
          : notification.payload;
      const selectedText =
        typeof notePayload.selected_text === "string" ? notePayload.selected_text : null;
      const noteText = typeof notePayload.note_text === "string" ? notePayload.note_text : null;
      const tags = Array.isArray(notePayload.tags)
        ? notePayload.tags.filter((tag): tag is string => typeof tag === "string")
        : [];
  
      const parts = [];
      if (selectedText) parts.push(`"${selectedText}"`);
      if (tags.length > 0) parts.push(tags.join(", "));
      if (noteText) parts.push(noteText);
  
      return parts.length > 0 ? parts.join(" · ") : i18n("workoutAnnotationSubmittedd0b2f39");
    }
  
    if (notification.type === "coaching_message" || notification.type === "box_message") {
      return typeof notification.payload.body === "string"
        ? notification.payload.body
        : i18n(notification.type === "coaching_message" ? "notifCoachingMessageBody" : "notifBoxMessageBody");
    }
  
    if (notification.type === "workout_changed") {
      if (typeof notification.payload?.body === "string") return notification.payload.body;
      const changeType = notification.payload?.change_type;
      if (changeType === "datetime_changed") return i18n("theScheduledTimeForThisWorkoutWasChanged2d953b3");
      if (changeType === "sections_updated") return i18n("yourCoachUpdatedTheExercisesInThisWorkout1c9eed2");
      return i18n("yourCoachChangedAScheduledWorkoutf8cf1d6");
    }
  
    if (notification.type === "workout_deleted") {
      return typeof notification.payload.body === "string"
        ? notification.payload.body
        : i18n("aScheduledWorkoutWasRemovedc3ae9af");
    }
  
    if (notification.type === "workout_rejected") {
      const nickname =
        typeof notification.payload.athlete_nickname === "string"
          ? notification.payload.athlete_nickname
          : i18n("anAthlete8f35f1a");
      const title =
        typeof notification.payload.workout_title === "string"
          ? i18n("value0f05883f", {value0: notification.payload.workout_title})
          : "";
      return i18n("value0RejectedTheirAssignedWorkoutValue15517fe5", {value0: nickname, value1: title});
    }
  
    if (notification.type === "athlete_message") {
      const sender =
        typeof notification.payload.sender_nickname === "string"
          ? notification.payload.sender_nickname
          : i18n("anAthlete8f35f1a");
      const body =
        typeof notification.payload.body === "string" ? notification.payload.body : "";
      return body ? i18n("value0Value10f13dbb", {value0: sender, value1: body}) : i18n("value0SentYouAMessage7c89010", {value0: sender});
    }
  
    if (notification.type === "chat_message") {
      const sender =
        typeof notification.payload.sender_nickname === "string"
          ? notification.payload.sender_nickname
          : null;
      const body =
        typeof notification.payload.body === "string" ? notification.payload.body : "";
      const contextType =
        typeof notification.payload.context_type === "string" ? notification.payload.context_type : null;
      const isWorkoutThread = contextType === "assignment" || contextType === "class_slot";
  
      if (sender && body) {
        return isWorkoutThread ? i18n("value0InYourWorkoutThreadValue1c868809", {value0: sender, value1: body}) : i18n("value0Value10f13dbb", {value0: sender, value1: body});
      }
      if (body) return body;
      return isWorkoutThread ? i18n("newMessageInYourWorkoutThreada646c0d") : i18n("youReceivedANewMessage465e15f");
    }
  
    if (notification.type === "challenge_completed") {
      if (typeof notification.payload.badge_label === "string") return notification.payload.badge_label;
      if (typeof notification.payload.title === "string") return notification.payload.title;
      return i18n("youCompletedAChallengedc085e6");
    }
  
    if (notification.type === "workout_moved") {
      return typeof notification.payload.body === "string"
        ? notification.payload.body
        : i18n("anAthleteRescheduledTheirWorkoutfe39f42");
    }

    if (notification.type === "workout_assignment_requested") {
      const nickname =
        typeof notification.payload.athlete_nickname === "string"
          ? notification.payload.athlete_nickname
          : i18n("anAthlete8f35f1a");
      const requestedFor =
        typeof notification.payload.requested_for === "string"
          ? notification.payload.requested_for
          : "";
      const note =
        typeof notification.payload.note === "string" ? notification.payload.note : "";
      return [nickname, requestedFor, note].filter(Boolean).join(" · ");
    }

    if (notification.type === "booking_waitlist_promoted") {
      const className =
        typeof notification.payload.class_name === "string" ? notification.payload.class_name : "";
      const scheduledAt =
        typeof notification.payload.scheduled_at === "string" ? notification.payload.scheduled_at : null;
      const when = scheduledAt && !Number.isNaN(new Date(scheduledAt).getTime())
        ? formatTimestamp(uiLocale, scheduledAt)
        : "";
      const detail = [className, when].filter(Boolean).join(" · ");
      return notification.payload.status === "pending"
        ? i18n("mbNotifWaitlistPromotedPendingBody", { class: detail })
        : i18n("mbNotifWaitlistPromotedBody", { class: detail });
    }

    if (notification.type === "package_expiring") {
      const packageName =
        typeof notification.payload.package_name === "string" ? notification.payload.package_name : "";
      const endsOn = typeof notification.payload.ends_on === "string" ? notification.payload.ends_on : null;
      const date = endsOn && !Number.isNaN(new Date(endsOn).getTime())
        ? new Intl.DateTimeFormat(uiLocale, { day: "numeric", month: "short", year: "numeric" }).format(new Date(endsOn))
        : "";
      return i18n("mbNotifPackageExpiringBody", { package: packageName, date });
    }

    const phaseCBody = coachingNotificationBody(notification);
    if (phaseCBody !== null) return phaseCBody;

    if (notification.type === "access_ended") {
      const payload = notification.payload;
      const reason = payload.reason === "overdue_payment" ? i18n("accessBlockedOverdue") : i18n("accessEnded");
      const cancelled = typeof payload.cancelled_bookings === "number" ? payload.cancelled_bookings : 0;
      return cancelled > 0 ? `${reason} ${i18n("accessEndedCancelledBookings", { count: cancelled })}` : reason;
    }

    if (notification.type === "subscription_expiring" || notification.type === "subscription_grace") {
      const payload = notification.payload;
      const packageName = typeof payload.package_name === "string" ? payload.package_name : i18n("yourSubscription");
      if (notification.type === "subscription_expiring") {
        return i18n("subscriptionEndsSoonBody", {
          package: packageName,
          date: formatDay(payload.ends_on),
          days: typeof payload.days_left === "number" ? payload.days_left : 0,
        });
      }
      return i18n("subscriptionEndedBody", {
        package: packageName,
        date: formatDay(payload.grace_until),
      });
    }

    if (notification.type === "review_submitted") {
      const rating =
        typeof notification.payload.rating === "number"
          ? `${notification.payload.rating}/5`
          : null;
      const targetType =
        typeof notification.payload.target_type === "string"
          ? notification.payload.target_type.replaceAll("_", " ")
          : null;
      return [targetType, rating].filter(Boolean).join(" · ") || i18n("notificationc18f8f2");
    }
  
    const classType =
      typeof notification.payload.class_type_name === "string" ? notification.payload.class_type_name : null;
    const adminMessage =
      typeof notification.payload.admin_message === "string" ? notification.payload.admin_message : null;
  
    const parts = [];
    if (classType) parts.push(classType);
    if (adminMessage) parts.push(adminMessage);
  
    return parts.length > 0 ? parts.join(" · ") : i18n("openTheScheduleToReviewTheLatestBooking36c10aa");
  }

  // ADR-098 coaching and appointment notifications.
  function coachingNotificationBody(notification: NotificationRecord): string | null {
    const text = (key: string) =>
      typeof notification.payload[key] === "string" ? (notification.payload[key] as string) : "";
    const when = (key: string) => {
      const value = text(key);
      return value && !Number.isNaN(new Date(value).getTime()) ? formatTimestamp(uiLocale, value) : "";
    };
    const kind = () =>
      text("kind") === "assessment" ? i18n("stfKindAssessment") : i18n("stfKindPtSession");
    const client = () => text("client_nickname") || i18n("stfAMember");

    switch (notification.type) {
      case "form_review_submitted":
        return [i18n("stfNotifFormReviewSubmittedBody", { client: client() }), text("exercise_name")]
          .filter(Boolean)
          .join(" · ");
      case "form_review_completed":
        return [i18n("stfNotifFormReviewCompletedBody"), text("exercise_name")].filter(Boolean).join(" · ");
      case "coaching_reply_overdue":
        return i18n("stfNotifReplyOverdueBody", { client: client(), time: when("due_at") || "—" });
      // ADR-176: a class still without its WOD on its day.
      case "class_workout_missing": {
        const values = { className: text("class_name") || "—", when: text("class_when") || "—" };
        const published = notification.payload.published !== false && notification.payload.published !== "false";
        if (!published) return i18n("ntfClassWodMissingDraftBody", values);
        return text("alert") === "hour_before"
          ? i18n("ntfClassWodMissingHourBody", values)
          : i18n("ntfClassWodMissingMorningBody", values);
      }
      // ADR-184 follow-up: the one reminder before an idle demo is archived.
      case "business_demo_idle":
        return i18n("ntfBusinessDemoIdleBody", {
          business: text("business_name") || "—",
          days: String(notification.payload.days_left ?? "—"),
        });
      case "nutrition_plan_updated":
        return text("title") || i18n("stfNotifNutritionPlanBody");
      case "appointment_booked":
        return i18n("stfNotifAppointmentBookedBody", { client: client(), kind: kind(), time: when("starts_at") || "—" });
      case "appointment_cancelled":
        return i18n("stfNotifAppointmentCancelledBody", { kind: kind(), time: when("starts_at") || "—" });
      // ADR-100, ADR-101, ADR-104.
      case "coach_client_assigned":
        return i18n("ntfCoachClientAssignedBody", { coach: text("coach_nickname") || "—", client: client() });
      case "coach_note_viewed":
        return i18n("ntfCoachNoteViewedBody", {
          reader: text("reader_nickname") || "—",
          client: client(),
          time: when("read_at") || "—",
        });
      case "inventory_repair_needed":
        return [text("machine_name"), text("body")].filter(Boolean).join(" · ");
      case "inventory_stock_low":
        return text("status") === "reported"
          ? [text("supply_name"), text("place"), text("note")].filter(Boolean).join(" · ")
          : i18n("ntfStockLowBody", { item: text("supply_name") || "—", quantity: String(notification.payload.quantity ?? "—") });
      case "inventory_digest": {
        const items = Array.isArray(notification.payload.highlights)
          ? (notification.payload.highlights as unknown[]).filter((item): item is string => typeof item === "string")
          : [];
        return items.length > 0 ? i18n("ntfDigestBody", { items: items.join(", ") }) : i18n("ntfDigestEmptyBody");
      }
      default:
        return null;
    }
  }

  function titleFromPayload(notification: NotificationRecord) {
    const passwordReset = passwordResetText(notification, "title");
    if (passwordReset !== null) return passwordReset;
    const buddy = buddyText(notification, "title");
    if (buddy !== null) return buddy;
    const season = seasonText(notification, "title");
    if (season !== null) return season;
    const shop = shopText(notification, "title");
    if (shop !== null) return shop;
    const partner = partnerText(notification, "title");
    if (partner !== null) return partner;
    const device = deviceText(notification, "title");
    if (device !== null) return device;
    const checkIn = checkInText(notification, "title");
    if (checkIn !== null) return checkIn;
    const around = aroundText(notification, "title");
    if (around !== null) return around;
    const trial = trialText(notification, "title");
    if (trial !== null) return trial;
    const referral = referralText(notification, "title");
    if (referral !== null) return referral;
    const community = communityText(notification, "title");
    if (community !== null) return community;
    // The nutrition plan's own title is the body, not the notification title.
    if (notification.type === "nutrition_plan_updated") return notificationTitle(notification.type);
    if (typeof notification.payload.title === "string") return notification.payload.title;
  
    if (notification.type === "chat_message") {
      const contextType =
        typeof notification.payload.context_type === "string" ? notification.payload.context_type : null;
      if (contextType === "assignment" || contextType === "class_slot") {
        return i18n("newMessageInWorkoutThreadbf823a6");
      }
    }
  
    return notificationTitle(notification.type);
  }

  function notificationTitle(type: string) {
    switch (type) {
      case "booking_pending":
        return i18n("newBookingRequest457ca72");
      case "booking_approved":
        return i18n("bookingApproved61fe8f8");
      case "booking_rejected":
        return i18n("bookingRejectede74f5ed");
      case "booking_timeout":
        return i18n("bookingTimedOut2ac6827");
      case "workout_note":
        return i18n("workoutAnnotation7b74f93");
      case "workout_changed":
        return i18n("workoutChanged8ae1481");
      case "workout_deleted":
        return i18n("workoutDeletedByCoachfb153d4");
      case "workout_rejected":
        return i18n("workoutRejected14068a6");
      case "athlete_message":
        return i18n("messageFromAthlete768702f");
      case "coaching_message":
        return i18n("notifCoachingMessage");
      case "box_message":
        return i18n("notifBoxMessage");
      case "chat_message":
        return i18n("newMessage1ed2e7b");
      case "challenge_completed":
        return i18n("challengeCompletedec1f9a3");
      case "workout_moved":
        return i18n("workoutRescheduledb1ead39");
      case "workout_assigned":
        return i18n("newWorkoutsAssigned");
      case "workout_assignment_requested":
        return i18n("notificationc18f8f2");
      case "review_submitted":
        return i18n("notificationc18f8f2");
      case "invoice_issued":
        return i18n("invoiceIssued6a8d8fa");
      case "payment_reminder":
        return i18n("outstandingBalancee9fd5bb");
      case "booking_waitlist_promoted":
        return i18n("mbNotifWaitlistPromotedTitle");
      case "package_expiring":
        return i18n("mbNotifPackageExpiringTitle");
      case "form_review_submitted":
        return i18n("stfNotifFormReviewSubmittedTitle");
      case "form_review_completed":
        return i18n("stfNotifFormReviewCompletedTitle");
      case "coaching_reply_overdue":
        return i18n("stfNotifReplyOverdueTitle");
      case "class_workout_missing":
        return i18n("ntfClassWodMissingTitle");
      case "business_demo_idle":
        return i18n("ntfBusinessDemoIdleTitle");
      case "nutrition_plan_updated":
        return i18n("stfNotifNutritionPlanTitle");
      case "appointment_booked":
        return i18n("stfNotifAppointmentBookedTitle");
      case "appointment_cancelled":
        return i18n("stfNotifAppointmentCancelledTitle");
      case "coach_client_assigned":
        return i18n("ntfCoachClientAssignedTitle");
      case "coach_note_viewed":
        return i18n("ntfCoachNoteViewedTitle");
      case "inventory_repair_needed":
        return i18n("ntfRepairNeededTitle");
      case "inventory_stock_low":
        return i18n("ntfStockLowTitle");
      case "inventory_digest":
        return i18n("ntfDigestTitle");
      case "subscription_expiring":
        return i18n("subscriptionEndsSoonTitle");
      case "subscription_grace":
        return i18n("subscriptionEndedTitle");
      case "access_ended":
        return i18n("accessEndedTitle");
      default:
        return i18n("notificationc18f8f2");
    }
  }
  const clickable = Boolean(targetUrl);

  return (
    <article
      key={notification.id}
      className="rounded-[1.4rem] p-4"
      onClick={clickable ? onClick : undefined}
      role={clickable ? "button" : undefined}
      style={{
        border: notification.read_at ? "1px solid var(--border)" : "1px solid color-mix(in srgb, var(--primary) 30%, transparent)",
        background: notification.read_at ? "var(--panel-muted)" : "color-mix(in srgb, var(--primary) 6%, transparent)",
        cursor: clickable ? "pointer" : "default",
        // Anything raised outside the active organization gets a colour spine
        // in that gym's own brand colour, so repeat senders stay recognisable.
        ...(origin
          ? { borderInlineStart: `4px solid ${origin.color ?? "var(--dim)"}` }
          : {}),
      }}
      tabIndex={clickable ? 0 : undefined}
      onKeyDown={
        clickable
          ? (event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                onClick();
              }
            }
          : undefined
      }
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          {origin ? (
            <span
              className="mb-2 inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-semibold"
              style={{
                background: origin.color
                  ? `color-mix(in srgb, ${origin.color} 14%, transparent)`
                  : "var(--border)",
                color: origin.color ?? "var(--text-soft)",
                border: `1px solid ${
                  origin.color
                    ? `color-mix(in srgb, ${origin.color} 40%, transparent)`
                    : "var(--border-strong)"
                }`,
              }}
            >
              <span
                aria-hidden="true"
                className="inline-block h-2 w-2 shrink-0 rounded-full"
                style={{ background: origin.color ?? "var(--dim)" }}
              />
              {origin.name}
            </span>
          ) : null}
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {titleFromPayload(notification)}
          </p>
          <p
            className="mt-2 whitespace-pre-wrap break-words text-sm leading-6 [overflow-wrap:anywhere]"
            data-user-text
            style={{ color: "var(--muted)" }}
          >
            {notificationBody(notification)}
          </p>
        </div>
        {!notification.read_at ? (
          <span
            className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]"
            style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          >
            {i18n("new6403f2b")}
          </span>
        ) : null}
      </div>
      <p className="mt-3 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {formatTimestamp(uiLocale, notification.inserted_at)}
      </p>
    </article>
  );
}

type FilterTab = "all" | "workouts" | "bookings";

const FILTER_TYPES: Record<FilterTab, string[] | null> = {
  all: null,
  workouts: [
    "workout_note",
    "workout_changed",
    "workout_deleted",
    "workout_rejected",
    "workout_moved",
    "workout_assignment_requested",
    "coaching_message",
    // ADR-098 coaching
    "form_review_submitted",
    "form_review_completed",
    "coaching_reply_overdue",
    "nutrition_plan_updated",
  ],
  bookings: [
    "booking_pending",
    "booking_approved",
    "booking_rejected",
    "booking_timeout",
    "booking_waitlist_promoted",
    // ADR-098 appointments
    "appointment_booked",
    "appointment_cancelled",
  ],
};

const OPEN_EVENT = "palee:open-notifications";

/** Opens the inbox from elsewhere, e.g. the avatar menu on phones (ADR-103). */
export function openNotifications() {
  window.dispatchEvent(new Event(OPEN_EVENT));
}

// The unread count, shared with other entry points such as ♡ in the Feed
// header (plan §5a Q11), without a second request.
let unreadSnapshot = 0;
const unreadListeners = new Set<() => void>();

function publishUnread(count: number) {
  if (count === unreadSnapshot) return;
  unreadSnapshot = count;
  unreadListeners.forEach((listener) => listener());
}

export function useUnreadNotifications() {
  return useSyncExternalStore(
    (listener) => {
      unreadListeners.add(listener);
      return () => unreadListeners.delete(listener);
    },
    () => unreadSnapshot,
    () => 0,
  );
}

const TRIAL_NOTICES = ["requested", "booked", "cancelled", "accepted", "declined", "reminder", "follow_up", "class_cancelled"] as const;
type TrialNotice = (typeof TRIAL_NOTICES)[number];
const TRIAL_NOTICE_KEYS = {
  requested: ["notif_requested_title", "notif_requested_body"],
  booked: ["notif_booked_title", "notif_booked_body"],
  cancelled: ["notif_cancelled_title", "notif_cancelled_body"],
  accepted: ["notif_accepted_title", "notif_accepted_body"],
  declined: ["notif_declined_title", "notif_declined_body"],
  reminder: ["notif_reminder_title", "notif_reminder_body"],
  follow_up: ["notif_follow_up_title", "notif_follow_up_body"],
  class_cancelled: ["notif_class_cancelled_title", "notif_class_cancelled_body"],
} as const satisfies Record<TrialNotice, readonly [string, string]>;

const COMMUNITY_NOTICES = [
  "community_group_proposed",
  "community_group_approved",
  "community_group_declined",
  "community_group_join_requested",
  "community_group_join_approved",
  "community_group_archive_warning",
  "community_report_created",
  "community_club_join_requested",
  "community_club_join_approved",
  "community_squad_invited",
  "community_event_waitlist_promoted",
  "community_event_cancelled",
  "community_event_changed",
  "community_event_reminder",
  "community_event_guest_joined",
  "community_event_trial_offer",
  "community_event_message",
  "community_event_cohost_request",
  "community_event_cohost_answered",
] as const;

export function NotificationBell({
  onUnreadChange,
  triggerClassName = "flex",
  hideTrigger = false,
}: {
  onUnreadChange?: (count: number) => void;
  triggerClassName?: string;
  /** Mount only the inbox: another control opens it (the member app's bottom bar). */
  hideTrigger?: boolean;
} = {}) {
  const i18n = useUiTranslations();
  const FILTER_TABS: { key: FilterTab; label: string }[] = [
    { key: "all", label: i18n("all6a72085") },
    { key: "workouts", label: i18n("workoutsccb58b2") },
    { key: "bookings", label: i18n("bookings135229c") },
  ];
  const pageSize = 20;
  const router = useRouter();
  const { status, tokens, currentUser } = useSession();
  const queryClient = useQueryClient();
  const activeOrganizationSlug = useOrganizationSlug();

  // Shares TanStack's cache with TopNav's identical query, so this costs no
  // extra request. Needed to resolve a notification's organization_id into a
  // name and brand colour.
  const membershipsQuery = useOrganizationMemberships();

  const organizations = useMemo(
    () =>
      (Array.isArray(membershipsQuery.data) ? membershipsQuery.data : []).map((membership) => ({
        id: membership.organization.id,
        name: membership.settings?.brand_name?.trim() || membership.organization.name,
        slug: membership.organization.slug,
      })),
    [membershipsQuery.data],
  );

  const activeOrganizationId =
    organizations.find((entry) => entry.slug === activeOrganizationSlug)?.id ?? null;

  const originFor = (notification: NotificationRecord) =>
    notificationOrigin(
      notification.organization_id,
      activeOrganizationId,
      organizations,
      i18n("anotherOrganization"),
    );
  const [open, setOpen] = useState(false);
  const [activeFilter, setActiveFilter] = useState<FilterTab>("all");
  const [pushHelpOpen, setPushHelpOpen] = useState(false);
  const push = usePushNotifications(tokens?.access_token);
  const notificationQuery = useInfiniteQuery({
    queryKey: ["notifications", currentUser?.id],
    enabled: status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser?.id),
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      if (!tokens?.access_token) {
        throw new Error(i18n("authenticationRequired9e44e0b"));
      }

      return fetchNotifications(tokens.access_token, {
        limit: pageSize,
        cursor: pageParam,
      });
    },
    getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
  });
  const markAllRead = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) {
        throw new Error(i18n("authenticationRequired9e44e0b"));
      }

      return markAllNotificationsRead(tokens.access_token);
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["notifications", currentUser?.id] });
    },
  });
  const markClicked = useMutation({
    mutationFn: async ({ notificationId, url }: { notificationId: string; url: string }) => {
      if (!tokens?.access_token) {
        throw new Error(i18n("authenticationRequired9e44e0b"));
      }

      return markNotificationClicked(tokens.access_token, notificationId, url);
    },
    onSuccess: async (_result, variables) => {
      queryClient.setQueryData(["notifications", currentUser?.id], (current: { pages: NotificationsResponse[]; pageParams: unknown[] } | undefined) => {
        if (!current) return current;

        return {
          ...current,
          pages: current.pages.map((page) => {
            let pageChanged = false;

            const notifications = page.notifications.map((notification) => {
              if (notification.id !== variables.notificationId || notification.read_at) {
                return notification;
              }

              pageChanged = true;
              return { ...notification, read_at: new Date().toISOString() };
            });

            if (!pageChanged) {
              return page;
            }

            return {
              ...page,
              notifications,
              unread_count: Math.max(0, page.unread_count - 1),
            };
          }),
        };
      });

      await queryClient.invalidateQueries({ queryKey: ["notifications", currentUser?.id] });
    },
  });

  useEffect(() => {
    if (status !== "authenticated" || !tokens?.access_token || !currentUser?.id) return;

    return subscribeToTopic(tokens.access_token, "notifications:" + (currentUser.id), {
      "notifications:changed": () => {
        void queryClient.invalidateQueries({ queryKey: ["notifications", currentUser.id] });
      },
    });
  }, [currentUser?.id, queryClient, status, tokens?.access_token]);

  const [readSectionOpen, setReadSectionOpen] = useState(false);

  const unreadCount = notificationQuery.data?.pages[0]?.unread_count;
  const allNotifications =
    notificationQuery.data?.pages.flatMap((page: NotificationsResponse) => page.notifications) ?? [];
  const filterTypes = FILTER_TYPES[activeFilter];
  const notifications = filterTypes
    ? allNotifications.filter((n) => filterTypes.includes(n.type))
    : allNotifications;
  const unreadNotifications = notifications.filter((n) => !n.read_at);
  const readNotifications = notifications.filter((n) => Boolean(n.read_at));
  const nextCursor = notificationQuery.data?.pages.at(-1)?.next_cursor ?? null;
  const hasUnread = typeof unreadCount === "number" && unreadCount > 0;
  const shouldShowPushControl = push.supported;
  const pushStatusMessage = (() => {
    if (push.error) {
      return push.error;
    }

    if (push.configured === false) {
      return i18n("browserPushIsNotConfiguredOnTheServerbf1bd61");
    }

    if (push.permission === "denied" || push.state === "blocked") {
      return i18n("browserPushIsBlockedInYourBrowserSettings0301fc4");
    }

    switch (push.step) {
      case "fetch-config":
        return i18n("checkingPushConfiguration4733bdc");
      case "register-worker":
        return i18n("registeringTheBrowserServiceWorker6ef3f3d");
      case "browser-subscription":
        return push.state === "enabling"
          ? i18n("creatingABrowserPushSubscription1bac6ad")
          : i18n("enableBrowserPushForApprovalsNotesAndAlerts4f4ec8d");
      case "server-save":
        return i18n("savingThisBrowserSubscriptionToTheServerd3589ad");
      case "server-verify":
        return i18n("verifyingThatTheServerPersistedThisBrowserSubscriptiona0178c5");
      default:
        return i18n("enableBrowserPushForApprovalsNotesAndAlerts4f4ec8d");
    }
  })();
  const pushStatusTone = push.error || push.configured === false ? "var(--primary)" : "var(--muted)";
  const pushButtonLabel = push.busy
    ? push.step === "server-save"
      ? i18n("savingae7e887")
      : i18n("enabling2b8e03e")
    : i18n("enable20063ad");
  const emptyMessage = useMemo(() => {
    if (notificationQuery.isPending) return i18n("loadingNotificationsf5e60c3");
    if (notificationQuery.isError && !notificationQuery.data) {
      return i18n("notificationsAreTemporarilyUnavailable9a64342");
    }
    if (markAllRead.isPending) return i18n("updatingNotifications27106ac");
    return i18n("noNotificationsYet5537c60");
  }, [i18n, markAllRead.isPending, notificationQuery.data, notificationQuery.isError, notificationQuery.isPending]);

  useEffect(() => {
    const count = typeof unreadCount === "number" ? unreadCount : 0;
    onUnreadChange?.(count);
    publishUnread(count);
  }, [onUnreadChange, unreadCount]);

  useEffect(() => {
    const handler = () => {
      setOpen(true);
      void notificationQuery.refetch();
    };
    window.addEventListener(OPEN_EVENT, handler);
    return () => window.removeEventListener(OPEN_EVENT, handler);
  }, [notificationQuery]);

  if (status !== "authenticated" || !tokens?.access_token) return null;

  function openPanel() {
    setOpen(true);
    void notificationQuery.refetch();
    void push.refreshCapability();
  }

  async function handleMarkAllRead() {
    if (!tokens?.access_token || !unreadCount) return;
    await markAllRead.mutateAsync();
  }

  async function handleNotificationClick(notification: NotificationRecord) {
    const url = notificationTargetUrl(notification, currentUser?.role);
    if (!url) return;

    if (!notification.read_at) {
      try {
        await markClicked.mutateAsync({ notificationId: notification.id, url });
      } catch {
        // Navigation should still proceed if marking the notification read fails.
      }
    }

    setOpen(false);
    router.push(url);
  }

  return (
    <>
      {hideTrigger ? null : (
        <button
          aria-expanded={open}
          aria-label={i18n("openNotificationsac4735e")}
          className={`${triggerClassName} shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-semibold transition-colors`}
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
          onClick={openPanel}
          type="button"
        >
          <NavIcon name="bell" size={18} strokeWidth={2} />
          {hasUnread ? (
            <span
              className="rounded-full px-1.5 py-0.5 text-[10px] font-bold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {unreadCount}
            </span>
          ) : null}
        </button>
      )}

      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          bare
          variant="drawer"
          size="md"
          ariaLabel={i18n("notifications753a22b")}
          panelClassName="overflow-y-auto p-6"
          panelStyle={{ paddingTop: "max(1.5rem, env(safe-area-inset-top))" }}
        >
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em] text-[var(--primary)]">{i18n("notifications753a22b")}</p>
                <h2 className="mt-3 text-2xl font-semibold" style={{ color: "var(--text)" }}>{i18n("inbox44caf74")}</h2>
              </div>
              <button
                className="rounded-full px-3 py-2 text-sm font-semibold transition-colors"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setOpen(false)}
                type="button"
              >
                {i18n("closebbfa773")}
              </button>
            </div>

            <FollowRequestsRow onNavigate={() => setOpen(false)} />

            <SegmentPicker
              className="mt-5"
              ariaLabel={i18n("notificationFilters")}
              semantics="radiogroup"
              value={activeFilter}
              onChange={(value) => { setActiveFilter(value); setReadSectionOpen(false); }}
              options={FILTER_TABS.map((tab) => ({ value: tab.key, label: tab.label }))}
            />

            {shouldShowPushControl && !push.enabled ? (
              <div
                className="mt-5 rounded-[1.2rem] p-4"
                style={{ border: "1px solid var(--border)", background: "var(--panel-muted)" }}
              >
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="text-sm font-semibold" style={{ color: push.enabled ? "var(--success)" : pushStatusTone }}>
                      {push.enabled ? i18n("browserPushIsOnForThisDevicea620272") : pushStatusMessage}
                    </p>
                    <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                      {i18n("thisChoiceAppliesOnlyToThisBrowserAnd0ca4181")}
                    </p>
                  </div>
                  {push.enabled ? (
                    <button
                      className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold"
                      style={{ border: "1px solid var(--border)", color: "var(--muted)" }}
                      disabled={push.busy}
                      onClick={() => void push.disablePush()}
                      type="button"
                    >
                      {push.busy ? i18n("disabling3bf14ec") : i18n("disable9a7d4e0")}
                    </button>
                  ) : push.permission !== "denied" && push.configured !== false ? (
                    <button
                      className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold"
                      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                      disabled={push.busy}
                      onClick={() => void push.enablePush()}
                      type="button"
                    >
                      {pushButtonLabel}
                    </button>
                  ) : (
                    <button
                      className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold"
                      style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                      onClick={() => setPushHelpOpen((current) => !current)}
                      type="button"
                    >
                      {currentUser?.role === "admin" ? i18n("setupcdd7bb2") : i18n("whatNowe1cd551")}
                    </button>
                  )}
                </div>
                {pushHelpOpen && push.configured === false ? (
                  <div className="mt-3 rounded-xl p-3 text-xs leading-5" style={{ background: "var(--panel)", color: "var(--muted)" }}>
                    {currentUser?.role === "admin"
                      ? i18n("generateAVapidKeyPairSetWebPushdabd06b")
                      : i18n("theGymServerHasNotEnabledBrowserPushe7cec31")}
                  </div>
                ) : pushHelpOpen && push.permission === "denied" ? (
                  <div className="mt-3 rounded-xl p-3 text-xs leading-5" style={{ background: "var(--panel)", color: "var(--muted)" }}>
                    {i18n("openThisSiteSPermissionsInYourBrowserdb34d1a")}
                  </div>
                ) : null}
              </div>
            ) : null}

            <div className="mt-6 space-y-4">
              {notifications.length === 0 ? (
                <div
                  className="rounded-[1.4rem] p-5 text-sm"
                  style={{ border: "1px solid var(--border)", color: "var(--dim)" }}
                >
                  {emptyMessage}
                </div>
              ) : null}

              {/* Unread section — default open */}
              {notifications.length > 0 ? (
                <section>
                  <div className="mb-3 flex items-center justify-between gap-3">
                    <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                      {i18n("new6403f2b")}
                      {unreadNotifications.length > 0 ? (
                        <span
                          className="ms-2 rounded-full px-1.5 py-0.5 text-[10px]"
                          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                        >
                          {unreadNotifications.length}
                        </span>
                      ) : null}
                    </p>
                    {hasUnread ? (
                      <button
                        className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
                        style={{ background: "var(--border)", color: "var(--text-soft)" }}
                        disabled={markAllRead.isPending}
                        onClick={() => void handleMarkAllRead()}
                        type="button"
                      >
                        {i18n("markAllRead8958e22")}
                      </button>
                    ) : null}
                  </div>
                  {unreadNotifications.length === 0 ? (
                    <p className="rounded-[1.4rem] px-4 py-3 text-sm" style={{ border: "1px solid var(--border)", color: "var(--dim)" }}>
                      {i18n("youReAllCaughtUp3d39c46")}
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {unreadNotifications.map((notification) => (
                        <NotificationCard
                          key={notification.id}
                          notification={notification}
                          targetUrl={notificationTargetUrl(notification, currentUser?.role)}
                          onClick={() => handleNotificationClick(notification)}
                          origin={originFor(notification)}
                        />
                      ))}
                    </div>
                  )}
                </section>
              ) : null}

              {/* Read section — default collapsed */}
              {readNotifications.length > 0 ? (
                <section>
                  <button
                    className="mb-3 flex w-full items-center justify-between gap-3"
                    onClick={() => setReadSectionOpen((v) => !v)}
                    type="button"
                  >
                    <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                      {i18n("read4de891c")}{readNotifications.length})
                    </p>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>
                      {readSectionOpen ? "▲" : "▼"}
                    </span>
                  </button>
                  {readSectionOpen ? (
                    <div className="space-y-3">
                      {readNotifications.map((notification) => (
                        <NotificationCard
                          key={notification.id}
                          notification={notification}
                          targetUrl={notificationTargetUrl(notification, currentUser?.role)}
                          onClick={() => handleNotificationClick(notification)}
                          origin={originFor(notification)}
                        />
                      ))}
                    </div>
                  ) : null}
                </section>
              ) : null}

              {notifications.length > 0 && nextCursor ? (
                <button
                  className="w-full rounded-[1.4rem] border px-4 py-3 text-sm font-semibold disabled:opacity-50"
                  style={{ borderColor: "var(--border)", color: "var(--text-soft)", background: "var(--panel-muted)" }}
                  disabled={notificationQuery.isFetchingNextPage}
                  onClick={() => void notificationQuery.fetchNextPage()}
                  type="button"
                >
                  {notificationQuery.isFetchingNextPage ? i18n("loadingOlderNotifications927e059") : i18n("loadOlderNotifications3447adb")}
                </button>
              ) : null}
            </div>
        </Dialog>
      ) : null}
    </>
  );
}

/** "2026-10-15" → a short local date; unknown values stay empty. */
function formatDay(value: unknown) {
  if (typeof value !== "string") return "";
  const date = new Date(`${value}T12:00:00`);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString(undefined, { day: "numeric", month: "short" });
}
