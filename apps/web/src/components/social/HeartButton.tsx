"use client";

import { useTranslations } from "next-intl";

import { openNotifications, useUnreadNotifications } from "@/components/notifications/NotificationBell";

/** ♡ Ειδοποιήσεις in the Feed header (vision §7.1, plan §5a Q11), with the unread count. */
export function HeartButton() {
  const t = useTranslations("Social");
  const unread = useUnreadNotifications();
  return (
    <button
      type="button"
      onClick={openNotifications}
      aria-label={unread > 0 ? t("notificationsUnread", { count: unread }) : t("notifications")}
      className="relative flex h-11 w-11 items-center justify-center rounded-full"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
    >
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
      </svg>
      {unread > 0 ? (
        <span
          aria-hidden="true"
          className="absolute -end-1 -top-1 min-w-5 rounded-full px-1 text-center text-[10px] font-bold leading-5"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {unread > 99 ? "99+" : unread}
        </span>
      ) : null}
    </button>
  );
}
