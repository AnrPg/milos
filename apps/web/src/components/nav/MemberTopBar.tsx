"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useRef, type ReactNode } from "react";

import { openNotifications, useUnreadNotifications } from "@/components/notifications/NotificationBell";

import { Badge, useBottomTabBarVisible } from "./BottomNav";
import { useBottomNavHiddenByScreen } from "./bottom-nav-visibility";
import { NavIcon } from "./NavIcons";
import { registerTopBarSlot } from "./top-bar-slot";
import { useScrollHidden } from "./use-scroll-hidden";

/**
 * The member app's top bar (owner, 2026-10-24, Instagram-like): the Palee
 * logo on the left, the bell on the right, and the page's own action next to
 * the bell (the Feed's ⊕, via <TopBarActions>). It shows wherever the bottom
 * bar does and, like it, slides away while scrolling down and comes back on
 * any scroll up. The page group's tab strip (`children`) rides with it.
 */
export function MemberTopBar({ children }: { children?: ReactNode }) {
  const t = useTranslations("Navigation");
  const tSocial = useTranslations("Social");
  const tUi = useTranslations("Ui");
  const pathname = usePathname();
  const visible = useBottomTabBarVisible();
  const hiddenByScreen = useBottomNavHiddenByScreen();
  const [scrollHidden, reveal] = useScrollHidden(visible, pathname);
  const unread = useUnreadNotifications();
  const barRef = useRef<HTMLElement>(null);
  const hidden = visible && scrollHidden && !hiddenByScreen;

  // --top-bar-space (globals.css): the room the bar takes while it shows.
  useEffect(() => {
    const root = document.documentElement;
    const bar = barRef.current;
    if (!visible || !bar) return;
    const update = () => {
      root.dataset.topBar = hidden ? "hidden" : "shown";
      root.style.setProperty("--top-bar-space", hidden ? "0px" : `${bar.offsetHeight}px`);
    };
    update();
    const observer = typeof ResizeObserver === "function" ? new ResizeObserver(update) : null;
    observer?.observe(bar);
    return () => {
      observer?.disconnect();
      delete root.dataset.topBar;
      root.style.removeProperty("--top-bar-space");
    };
  }, [visible, hidden]);

  if (!visible) {
    return children ? (
      <div className="sticky z-(--z-nav) overflow-x-clip pt-2" style={{ top: "var(--safe-top, 0px)", background: "var(--bg)", borderBottom: "1px solid var(--border)" }}>
        {children}
      </div>
    ) : null;
  }

  const label = unread > 0 ? tSocial("notificationsUnread", { count: unread }) : t("notifications");

  return (
    <header
      ref={barRef}
      data-testid="member-top-bar"
      data-state={hidden ? "hidden" : "shown"}
      onFocus={reveal}
      className="sticky z-(--z-nav) overflow-x-clip transition-transform duration-300 ease-out motion-reduce:transition-none"
      style={{
        // ADR-171: below the status bar inside the store apps (0 on the web).
        top: "var(--safe-top, 0px)",
        background: "color-mix(in srgb, var(--bg) 88%, transparent)",
        backdropFilter: "blur(18px) saturate(1.5)",
        WebkitBackdropFilter: "blur(18px) saturate(1.5)",
        borderBottom: "1px solid var(--border)",
        transform: hidden ? "translateY(calc(-100% - var(--safe-top, 0px)))" : "none",
      }}
    >
      <div className="mx-auto flex h-[3.25rem] w-full max-w-xl items-center justify-between gap-3 px-4">
        <Link href="/" className="rounded-md text-xl font-extrabold tracking-tight outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]" style={{ color: "var(--text)" }}>
          {tUi("brandName")}
        </Link>
        <div className="flex items-center gap-2">
          <div ref={registerTopBarSlot} className="flex items-center gap-2" />
          <button
            type="button"
            onClick={openNotifications}
            aria-label={label}
            title={t("notifications")}
            className="relative flex h-11 w-11 items-center justify-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
            style={{ color: "var(--text)" }}
          >
            <span className="relative">
              <NavIcon name="bell" />
              <Badge count={unread} />
            </span>
          </button>
        </div>
      </div>
      {children ? <div className="pt-1">{children}</div> : null}
    </header>
  );
}
