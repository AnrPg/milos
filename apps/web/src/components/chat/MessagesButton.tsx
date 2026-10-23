"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchUnreadCount } from "@/api/messaging";
import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";
import { NavIcon } from "@/components/nav/NavIcons";
import { useSession } from "@/components/session-provider";
import { HeartButton } from "@/components/social/HeartButton";
import { BELL_IN_BOTTOM_NAV } from "@/lib/bottom-nav";
import { useOrganizationSlug } from "@/lib/organization-slug";

/**
 * ✈ Μηνύματα, top-right of the Feed (brief §6.1), with the unread count. The
 * count shares TopNav's query key, so its realtime refresh updates it too.
 */
export function MessagesButton() {
  const t = useTranslations("Navigation");
  const { status, tokens, currentUser } = useSession();
  const slug = useOrganizationSlug();
  const [open, setOpen] = useState(false);
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser);
  const unreadQuery = useQuery({
    queryKey: ["messages", "unread", slug],
    enabled: authenticated && Boolean(slug),
    queryFn: () => fetchUnreadCount(tokens!.access_token, slug),
    staleTime: 15 * 1000,
  });
  const unread = unreadQuery.data?.unread_count ?? 0;

  if (!authenticated) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={unread > 0 ? t("messagesUnread", { count: unread }) : t("messages")}
        title={t("messages")}
        className="relative flex h-11 w-11 items-center justify-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        <NavIcon name="messages" size={20} strokeWidth={2} />
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
      {open ? <DirectMessagesPanel onClose={() => setOpen(false)} /> : null}
    </>
  );
}

/**
 * The Feed header's inbox buttons: ✈ always; ♡ only in the 4-tab fallback,
 * when the bell is not in the bottom bar (lib/bottom-nav.ts).
 */
export function FeedInboxButtons() {
  return (
    <>
      {BELL_IN_BOTTOM_NAV ? null : <HeartButton />}
      <MessagesButton />
    </>
  );
}
