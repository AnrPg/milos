"use client";

import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";

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

function formatTimestamp(isoString: string) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(isoString));
}

function notificationTitle(type: string) {
  switch (type) {
    case "booking_pending":
      return "New booking request";
    case "booking_approved":
      return "Booking approved";
    case "booking_rejected":
      return "Booking rejected";
    case "booking_timeout":
      return "Booking timed out";
    case "workout_note":
      return "Workout annotation";
    case "workout_changed":
      return "Workout changed";
    case "workout_deleted":
      return "Workout deleted by coach";
    case "workout_rejected":
      return "Workout rejected";
    case "athlete_message":
      return "Message from athlete";
    case "admin_note":
      return "Coach note";
    case "chat_message":
      return "New message";
    case "challenge_completed":
      return "Challenge completed";
    case "workout_moved":
      return "Workout rescheduled";
    case "invoice_issued":
      return "Invoice issued";
    case "payment_reminder":
      return "Outstanding balance";
    default:
      return "Notification";
  }
}

function payloadUrl(notification: NotificationRecord) {
  return typeof notification.payload.url === "string" ? notification.payload.url : null;
}

function notificationTargetUrl(notification: NotificationRecord, role: string | null | undefined) {
  const rawUrl = payloadUrl(notification);
  const isAdmin = role === "admin" || role === "coach";

  if (notification.type === "chat_message" && typeof notification.payload.thread_id === "string") {
    return `/account/activity/chats?thread=${encodeURIComponent(notification.payload.thread_id)}`;
  }

  if (!rawUrl) return null;
  if (!isAdmin) return rawUrl;

  const [path, query = ""] = rawUrl.split("?");
  const params = new URLSearchParams(query);

  if (path === "/my-workouts") {
    const assignmentId = params.get("open") ?? params.get("open_assignment");
    if (!assignmentId) return "/admin/coaching-assignments";

    const nextParams = new URLSearchParams({ open: assignmentId });
    const date = params.get("date");
    if (date) nextParams.set("date", date);
    return `/admin/coaching-assignments?${nextParams.toString()}`;
  }

  if (path === "/schedule") {
    const nextParams = params.toString();
    return `/admin/schedule${nextParams ? `?${nextParams}` : ""}`;
  }

  return rawUrl;
}

function titleFromPayload(notification: NotificationRecord) {
  if (typeof notification.payload.title === "string") return notification.payload.title;

  if (notification.type === "chat_message") {
    const contextType =
      typeof notification.payload.context_type === "string" ? notification.payload.context_type : null;
    if (contextType === "assignment" || contextType === "class_slot") {
      return "New message in workout thread";
    }
  }

  return notificationTitle(notification.type);
}

function notificationBody(notification: NotificationRecord) {
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

    return parts.length > 0 ? parts.join(" · ") : "Workout annotation submitted.";
  }

  if (notification.type === "admin_note") {
    return typeof notification.payload.body === "string"
      ? notification.payload.body
      : "Your coach added a new note.";
  }

  if (notification.type === "workout_changed") {
    if (typeof notification.payload?.body === "string") return notification.payload.body;
    const changeType = notification.payload?.change_type;
    if (changeType === "datetime_changed") return "The scheduled time for this workout was changed.";
    if (changeType === "sections_updated") return "Your coach updated the exercises in this workout.";
    return "Your coach changed a scheduled workout.";
  }

  if (notification.type === "workout_deleted") {
    return typeof notification.payload.body === "string"
      ? notification.payload.body
      : "A scheduled workout was removed.";
  }

  if (notification.type === "workout_rejected") {
    const nickname =
      typeof notification.payload.athlete_nickname === "string"
        ? notification.payload.athlete_nickname
        : "An athlete";
    const title =
      typeof notification.payload.workout_title === "string"
        ? ` — ${notification.payload.workout_title}`
        : "";
    return `${nickname} rejected their assigned workout${title}.`;
  }

  if (notification.type === "athlete_message") {
    const sender =
      typeof notification.payload.sender_nickname === "string"
        ? notification.payload.sender_nickname
        : "An athlete";
    const body =
      typeof notification.payload.body === "string" ? notification.payload.body : "";
    return body ? `${sender}: ${body}` : `${sender} sent you a message.`;
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
      return isWorkoutThread ? `${sender} in your workout thread: ${body}` : `${sender}: ${body}`;
    }
    if (body) return body;
    return isWorkoutThread ? "New message in your workout thread." : "You received a new message.";
  }

  if (notification.type === "challenge_completed") {
    if (typeof notification.payload.badge_label === "string") return notification.payload.badge_label;
    if (typeof notification.payload.title === "string") return notification.payload.title;
    return "You completed a challenge.";
  }

  if (notification.type === "workout_moved") {
    return typeof notification.payload.body === "string"
      ? notification.payload.body
      : "An athlete rescheduled their workout.";
  }

  const trainingType =
    typeof notification.payload.training_type === "string" ? notification.payload.training_type : null;
  const adminMessage =
    typeof notification.payload.admin_message === "string" ? notification.payload.admin_message : null;

  const parts = [];
  if (trainingType) parts.push(trainingType.replaceAll("_", " ").replace(/\b\w/g, (char) => char.toUpperCase()));
  if (adminMessage) parts.push(adminMessage);

  return parts.length > 0 ? parts.join(" · ") : "Open the schedule to review the latest booking state.";
}

function NotificationCard({
  notification,
  targetUrl,
  onClick,
}: {
  notification: NotificationRecord;
  targetUrl: string | null;
  onClick: () => void;
}) {
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
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {titleFromPayload(notification)}
          </p>
          <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>
            {notificationBody(notification)}
          </p>
        </div>
        {!notification.read_at ? (
          <span
            className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            New
          </span>
        ) : null}
      </div>
      <p className="mt-3 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {formatTimestamp(notification.inserted_at)}
      </p>
    </article>
  );
}

type FilterTab = "all" | "workouts" | "bookings" | "messages";

const FILTER_TABS: { key: FilterTab; label: string }[] = [
  { key: "all", label: "All" },
  { key: "workouts", label: "Workouts" },
  { key: "bookings", label: "Bookings" },
  { key: "messages", label: "Messages" },
];

const FILTER_TYPES: Record<FilterTab, string[] | null> = {
  all: null,
  workouts: ["workout_note", "workout_changed", "workout_deleted", "workout_rejected", "workout_moved", "admin_note"],
  bookings: ["booking_pending", "booking_approved", "booking_rejected", "booking_timeout"],
  messages: ["athlete_message", "chat_message"],
};

export function NotificationBell() {
  const pageSize = 20;
  const router = useRouter();
  const { status, tokens, currentUser } = useSession();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [activeFilter, setActiveFilter] = useState<FilterTab>("all");
  const push = usePushNotifications(tokens?.access_token);
  const notificationQuery = useInfiniteQuery({
    queryKey: ["notifications", currentUser?.id],
    enabled: status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser?.id),
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      if (!tokens?.access_token) {
        throw new Error("Authentication required.");
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
        throw new Error("Authentication required.");
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
        throw new Error("Authentication required.");
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

    return subscribeToTopic(tokens.access_token, `notifications:${currentUser.id}`, {
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
  const shouldShowPushPrompt = push.supported && !push.enabled;
  const pushStatusMessage = (() => {
    if (push.error) {
      return push.error;
    }

    if (push.configured === false) {
      return "Browser push is not configured on the server yet.";
    }

    if (push.permission === "denied" || push.state === "blocked") {
      return "Browser push is blocked in your browser settings.";
    }

    switch (push.step) {
      case "fetch-config":
        return "Checking push configuration...";
      case "register-worker":
        return "Registering the browser service worker...";
      case "browser-subscription":
        return push.state === "enabling"
          ? "Creating a browser push subscription..."
          : "Enable browser push for approvals, notes, and alerts.";
      case "server-save":
        return "Saving this browser subscription to the server...";
      case "server-verify":
        return "Verifying that the server persisted this browser subscription...";
      default:
        return "Enable browser push for approvals, notes, and alerts.";
    }
  })();
  const pushStatusTone = push.error || push.configured === false ? "var(--primary)" : "var(--muted)";
  const pushButtonLabel = push.busy
    ? push.step === "server-save"
      ? "Saving..."
      : "Enabling..."
    : "Enable";
  const emptyMessage = useMemo(() => {
    if (notificationQuery.isPending) return "Loading notifications...";
    if (notificationQuery.isError && !notificationQuery.data) {
      return "Notifications are temporarily unavailable.";
    }
    if (markAllRead.isPending) return "Updating notifications...";
    return "No notifications yet.";
  }, [markAllRead.isPending, notificationQuery.data, notificationQuery.isError, notificationQuery.isPending]);

  if (status !== "authenticated" || !tokens?.access_token) return null;

  function openPanel() {
    setOpen(true);
    void notificationQuery.refetch();
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
      <button
        aria-expanded={open}
        aria-label="Open notifications"
        className="flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-semibold transition-colors"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        onClick={openPanel}
        type="button"
      >
        <span>📥</span>
        {hasUnread ? (
          <span
            className="rounded-full px-1.5 py-0.5 text-[10px] font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {unreadCount}
          </span>
        ) : null}
      </button>

      {open ? (
        <div
          className="fixed inset-0 z-30"
          style={{ background: "rgba(0,0,0,0.55)" }}
          onClick={() => setOpen(false)}
          role="presentation"
        >
          <aside
            className="absolute right-0 top-0 h-full w-full max-w-md overflow-y-auto p-6 shadow-[-20px_0_60px_rgba(0,0,0,0.5)]"
            style={{ background: "var(--panel)", borderLeft: "1px solid var(--border)" }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em] text-[var(--primary)]">Notifications</p>
                <h2 className="mt-3 text-2xl font-semibold" style={{ color: "var(--text)" }}>Inbox</h2>
              </div>
              <button
                className="rounded-full px-3 py-2 text-sm font-semibold transition-colors"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setOpen(false)}
                type="button"
              >
                Close
              </button>
            </div>

            <div className="mt-5 flex gap-2 overflow-x-auto pb-1">
              {FILTER_TABS.map((tab) => (
                <button
                  key={tab.key}
                  className="shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                  style={
                    activeFilter === tab.key
                      ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                      : { background: "var(--border)", color: "var(--muted)" }
                  }
                  onClick={() => { setActiveFilter(tab.key); setReadSectionOpen(false); }}
                  type="button"
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {shouldShowPushPrompt ? (
              <div
                className="mt-5 rounded-[1.2rem] p-4"
                style={{ border: "1px solid var(--border)", background: "var(--panel-muted)" }}
              >
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm" style={{ color: pushStatusTone }}>
                    {pushStatusMessage}
                  </p>
                  {push.permission !== "denied" && push.configured !== false ? (
                    <button
                      className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold"
                      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                      disabled={push.busy}
                      onClick={() => void push.enablePush()}
                      type="button"
                    >
                      {pushButtonLabel}
                    </button>
                  ) : null}
                </div>
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
                      New
                      {unreadNotifications.length > 0 ? (
                        <span
                          className="ml-2 rounded-full px-1.5 py-0.5 text-[10px]"
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
                        Mark all read
                      </button>
                    ) : null}
                  </div>
                  {unreadNotifications.length === 0 ? (
                    <p className="rounded-[1.4rem] px-4 py-3 text-sm" style={{ border: "1px solid var(--border)", color: "var(--dim)" }}>
                      You&apos;re all caught up.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {unreadNotifications.map((notification) => (
                        <NotificationCard
                          key={notification.id}
                          notification={notification}
                          targetUrl={notificationTargetUrl(notification, currentUser?.role)}
                          onClick={() => handleNotificationClick(notification)}
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
                      Read ({readNotifications.length})
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
                  {notificationQuery.isFetchingNextPage ? "Loading older notifications..." : "Load older notifications"}
                </button>
              ) : null}
            </div>
          </aside>
        </div>
      ) : null}
    </>
  );
}
