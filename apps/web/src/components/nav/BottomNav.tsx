"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState, type ReactNode } from "react";

import { ProfileSwitcherMenu } from "@/components/account/ProfileSwitcherMenu";
import { openNotifications, useUnreadNotifications } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";
import { Popover } from "@/components/ui/Popover";
import { bottomNavEntries, nextScrollHidden, routeShowsBottomNav, usesMemberShell } from "@/lib/bottom-nav";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { activeItemId, clientNavItems } from "@/lib/role-navigation";

import { useBottomNavHiddenByScreen } from "./bottom-nav-visibility";
import { NavIcon, type NavIconName } from "./NavIcons";

/** Whether this account navigates with the bottom bar (the member shell). */
export function useMemberShell() {
  const { currentUser } = useSession();
  const { role, memberships, isLoading } = useSelectedMembershipRole();
  return usesMemberShell({
    signedIn: Boolean(currentUser),
    loading: isLoading,
    membershipCount: memberships.length,
    surfaceRole: role,
    vendor: Boolean(currentUser?.vendor),
    accountRole: currentUser?.role ?? null,
  });
}

/** Whether the bar shows on this route, so other fixed bars can sit above it. */
export function useBottomTabBarVisible() {
  const pathname = usePathname();
  return useMemberShell() && routeShowsBottomNav(pathname);
}

/**
 * The room the floating bar takes at the bottom of the screen, safe area
 * included (0 where the bar does not show). Set in globals.css.
 */
export const BOTTOM_NAV_SPACE = "var(--bottom-nav-space)";

const TAB_ICONS: Record<string, NavIconName> = { home: "feed", box: "box", journal: "journal" };

function prefersReducedMotion() {
  return typeof window !== "undefined" && typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Instagram-like: the bar slides away while scrolling down and returns on any
 * scroll up. Not with reduced motion. A new page always starts with it shown.
 */
function useScrollHidden(enabled: boolean, pathname: string) {
  // The page it was hidden on; another page shows it again.
  const [hiddenOn, setHiddenOn] = useState<string | null>(null);
  const state = useRef({ hidden: false, lastY: 0 });

  useEffect(() => {
    state.current = { hidden: false, lastY: window.scrollY };
    if (!enabled || prefersReducedMotion()) return;
    let frame = 0;
    const onScroll = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        const y = window.scrollY;
        const next = nextScrollHidden(state.current, y);
        if (Math.abs(y - state.current.lastY) >= 8 || next !== state.current.hidden) state.current.lastY = y;
        if (next !== state.current.hidden) {
          state.current.hidden = next;
          setHiddenOn(next ? pathname : null);
        }
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, [enabled, pathname]);

  const reveal = () => {
    state.current.hidden = false;
    setHiddenOn(null);
  };
  return [enabled && hiddenOn === pathname, reveal] as const;
}

function Badge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span
      aria-hidden="true"
      data-testid="bottom-nav-badge"
      className="absolute -end-2 -top-1.5 flex h-[1.125rem] min-w-[1.125rem] items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none"
      style={{ background: "var(--danger)", color: "var(--danger-contrast)", boxShadow: "0 0 0 2px var(--panel)" }}
    >
      {count > 99 ? "99+" : count}
    </span>
  );
}

const ITEM_CLASS =
  "relative flex min-h-14 min-w-0 flex-col items-center justify-center gap-0.5 rounded-[1.25rem] px-1 text-[10.5px] leading-tight outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[var(--primary)] motion-reduce:transition-none";

function ItemBody({ icon, label, current }: { icon: ReactNode; label: string; current: boolean }) {
  return (
    <>
      <span
        className="relative flex h-8 w-12 items-center justify-center rounded-full transition-colors motion-reduce:transition-none"
        // The current tab is Spark (ANR 2026-10-24), the icon dark on it.
        style={current ? { background: "var(--spark)", color: "var(--spark-contrast)" } : { background: "transparent" }}
      >
        {icon}
      </span>
      <span className={`max-w-full truncate ${current ? "font-bold" : "font-semibold"}`}>{label}</span>
    </>
  );
}

/**
 * The member app's floating bottom bar (brief §6.1; owner, 2026-10-23):
 * Feed · Box · Journal · Ειδοποιήσεις · avatar (Εγώ). It floats over the page
 * with side margins, a slightly see-through blurred background and rounded
 * corners; it steps aside on the focused flows of lib/bottom-nav.ts, for any
 * screen that calls useHideBottomNav(), and while scrolling down.
 */
export function BottomNav() {
  const t = useTranslations("Navigation");
  const tSocial = useTranslations("Social");
  const pathname = usePathname();
  const { currentUser } = useSession();
  const visible = useBottomTabBarVisible();
  const hiddenByScreen = useBottomNavHiddenByScreen();
  const [scrollHidden, reveal] = useScrollHidden(visible, pathname);
  const unread = useUnreadNotifications();
  const avatarRef = useRef<HTMLAnchorElement>(null);
  const longPress = useRef<{ timer: number; fired: boolean }>({ timer: 0, fired: false });
  const [switcherOpen, setSwitcherOpen] = useState(false);

  // One CSS variable gives every page its bottom room (globals.css).
  useEffect(() => {
    const root = document.documentElement;
    if (visible) root.dataset.bottomNav = "on";
    else delete root.dataset.bottomNav;
    return () => {
      delete root.dataset.bottomNav;
    };
  }, [visible]);

  if (!visible || !currentUser) return null;

  const hidden = hiddenByScreen || scrollHidden;
  const active = activeItemId(pathname, clientNavItems());
  const entries = bottomNavEntries();
  const hasOtherProfiles = (currentUser.profile_count ?? 1) > 1;
  const initials = currentUser.nickname ? currentUser.nickname.slice(0, 2).toUpperCase() : "?";

  // ADR-187: a long press (or a secondary click) on the avatar switches profile.
  const startLongPress = () => {
    if (!hasOtherProfiles) return;
    longPress.current.fired = false;
    window.clearTimeout(longPress.current.timer);
    longPress.current.timer = window.setTimeout(() => {
      longPress.current.fired = true;
      setSwitcherOpen(true);
    }, 500);
  };
  const cancelLongPress = () => window.clearTimeout(longPress.current.timer);

  return (
    <nav
      aria-label={t("memberTabs")}
      aria-hidden={hiddenByScreen ? true : undefined}
      inert={hiddenByScreen}
      data-testid="bottom-nav"
      data-state={hidden ? "hidden" : "shown"}
      onFocus={reveal}
      className="pointer-events-none fixed inset-x-0 bottom-0 z-(--z-nav) flex justify-center px-3"
      style={{ paddingBottom: "var(--bottom-nav-offset)" }}
    >
      <ul
        className={`${hidden ? "pointer-events-none" : "pointer-events-auto"} grid w-full max-w-md items-stretch gap-0.5 rounded-[1.75rem] p-1 transition-[transform,opacity] duration-300 ease-out motion-reduce:transition-none`}
        style={{
          gridTemplateColumns: `repeat(${entries.length}, minmax(0, 1fr))`,
          height: "var(--bottom-nav-height)",
          background: "color-mix(in srgb, var(--panel) 78%, transparent)",
          backdropFilter: "blur(18px) saturate(1.5)",
          WebkitBackdropFilter: "blur(18px) saturate(1.5)",
          border: "1px solid color-mix(in srgb, var(--border) 80%, transparent)",
          boxShadow: "var(--shadow-lg)",
          transform: hidden ? "translateY(calc(100% + var(--bottom-nav-offset) + 1rem))" : "none",
          opacity: hidden ? 0 : 1,
        }}
      >
        {entries.map((entry) => {
          if (entry.kind === "notifications") {
            const label = unread > 0 ? tSocial("notificationsUnread", { count: unread }) : t("notifications");
            return (
              <li key="notifications" className="flex min-w-0">
                <button
                  type="button"
                  onClick={openNotifications}
                  aria-label={label}
                  title={t("notifications")}
                  className={`${ITEM_CLASS} w-full`}
                  style={{ color: "var(--dim)" }}
                >
                  <ItemBody
                    current={false}
                    icon={
                      <span className="relative">
                        <NavIcon name="bell" />
                        <Badge count={unread} />
                      </span>
                    }
                    label={t("notificationsShort")}
                  />
                </button>
              </li>
            );
          }

          const item = entry.item;
          const current = item.id === active;
          const color = current ? "var(--text)" : "var(--dim)";

          if (entry.kind === "me") {
            return (
              <li key="me" className="flex min-w-0">
                {/* Full prefetch: a tap renders from the client cache (staleTimes in next.config.ts). */}
                <Link
                  ref={avatarRef}
                  href={item.href}
                  prefetch
                  aria-current={current ? "page" : undefined}
                  aria-label={t("me")}
                  className={`${ITEM_CLASS} w-full`}
                  style={{ color }}
                  onPointerDown={startLongPress}
                  onPointerUp={cancelLongPress}
                  onPointerLeave={cancelLongPress}
                  onPointerCancel={cancelLongPress}
                  onContextMenu={(event) => {
                    if (!hasOtherProfiles) return;
                    event.preventDefault();
                    cancelLongPress();
                    setSwitcherOpen(true);
                  }}
                  onClick={(event) => {
                    if (longPress.current.fired) {
                      event.preventDefault();
                      longPress.current.fired = false;
                    }
                  }}
                >
                  <ItemBody
                    current={false}
                    icon={
                      currentUser.avatar_url ? (
                        // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
                        <img
                          src={currentUser.avatar_url}
                          alt=""
                          draggable={false}
                          className="h-7 w-7 rounded-full object-cover"
                          style={{ boxShadow: current ? "0 0 0 2px var(--spark)" : "0 0 0 1px var(--border)" }}
                        />
                      ) : (
                        <span
                          aria-hidden="true"
                          className="flex h-7 w-7 items-center justify-center rounded-full text-[11px] font-bold"
                          style={{
                            background: "var(--primary)",
                            color: "var(--primary-contrast)",
                            boxShadow: current ? "0 0 0 2px var(--bg), 0 0 0 4px var(--spark)" : "none",
                          }}
                        >
                          {initials}
                        </span>
                      )
                    }
                    label={t(item.labelKey)}
                  />
                  {current ? <CurrentMark /> : null}
                </Link>
                <Popover
                  anchorRef={avatarRef}
                  open={switcherOpen}
                  onClose={() => setSwitcherOpen(false)}
                  align="end"
                  width={240}
                  ariaLabel={t("switchProfile")}
                  className="rounded-2xl py-1 shadow-[var(--shadow-lg)]"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                >
                  <ProfileSwitcherMenu />
                </Popover>
              </li>
            );
          }

          return (
            <li key={item.id} className="flex min-w-0">
              <Link
                href={item.href}
                prefetch
                aria-current={current ? "page" : undefined}
                className={`${ITEM_CLASS} w-full`}
                style={{ color }}
              >
                <ItemBody current={current} icon={<NavIcon name={TAB_ICONS[item.id] ?? "feed"} strokeWidth={current ? 2.2 : 1.8} />} label={t(item.labelKey)} />
                {current ? <CurrentMark /> : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/** A small dot under the active tab, so the state never rests on colour alone. */
function CurrentMark() {
  return <span aria-hidden="true" className="absolute bottom-0.5 h-1 w-1 rounded-full" style={{ background: "var(--text)" }} />;
}
