"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";

import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { activeItemId, clientNavItems, showsBottomBar } from "@/lib/role-navigation";

type TabIcon = "home" | "box" | "journal" | "me";

function Icon({ name }: { name: TabIcon }) {
  const common = {
    width: 24,
    height: 24,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };
  switch (name) {
    case "home":
      return (
        <svg {...common}>
          <path d="M3 10.5 12 3l9 7.5" />
          <path d="M5 9.5V21h5v-6h4v6h5V9.5" />
        </svg>
      );
    case "box":
      return (
        <svg {...common}>
          <path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11" />
        </svg>
      );
    case "journal":
      return (
        <svg {...common}>
          <path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5v-15Z" />
          <path d="M5 19.5A1.5 1.5 0 0 0 6.5 21H19v-3" />
        </svg>
      );
    case "me":
      return (
        <svg {...common}>
          <circle cx="12" cy="8" r="4" />
          <path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" />
        </svg>
      );
  }
}

/** Whether the tab bar shows here, so other fixed bars can sit above it. */
export function useBottomTabBarVisible() {
  const pathname = usePathname();
  const { currentUser } = useSession();
  const { role, memberships, isLoading } = useSelectedMembershipRole();
  if (!currentUser || isLoading || memberships.length === 0) return false;
  return role !== "admin" && showsBottomBar(pathname);
}

/** Height of the tab bar, safe area included. */
export const BOTTOM_TAB_BAR_HEIGHT = "calc(4.25rem + env(safe-area-inset-bottom))";

/**
 * The member app's fixed bottom bar (ADR-137, brief §6.1): four tabs that
 * never change order or hide, so the app stays predictable (brief §4.2).
 */
export function BottomTabBar() {
  const t = useTranslations("Navigation");
  const pathname = usePathname();
  const visible = useBottomTabBarVisible();

  if (!visible) return null;

  const items = clientNavItems();
  const active = activeItemId(pathname, items);

  return (
    <>
      {/* Keeps the last card of every page clear of the fixed bar. */}
      <div aria-hidden="true" style={{ height: BOTTOM_TAB_BAR_HEIGHT }} />
      <nav
        aria-label={t("memberTabs")}
        className="fixed inset-x-0 bottom-0 z-50 grid grid-cols-4"
        style={{
          background: "var(--bg)",
          borderTop: "1px solid var(--border)",
          paddingBottom: "env(safe-area-inset-bottom)",
        }}
      >
        {items.map((item) => {
          const current = item.id === active;
          return (
            <Link
              key={item.id}
              href={item.href}
              aria-current={current ? "page" : undefined}
              className="flex min-h-[4.25rem] flex-col items-center justify-center gap-1 text-xs font-semibold"
              style={{ color: current ? "var(--primary-strong)" : "var(--dim)" }}
            >
              <Icon name={item.id as TabIcon} />
              <span>{t(item.labelKey)}</span>
            </Link>
          );
        })}
      </nav>
    </>
  );
}
