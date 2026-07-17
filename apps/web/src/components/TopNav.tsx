"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchMyFinance } from "@/api/my-finance";
import { fetchUnreadCount } from "@/api/messaging";
import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";
import { SemanticLabel } from "@/components/semantic-label";

const CANVAS_PATHS = ["/login"];

type UserRole = "member" | "athlete" | "admin";

type NavLink = { href: string; labelKey: string; roles: UserRole[] };
type AdminNavLink = { href: string; labelKey: string; mobileVisible: boolean };

const NAV_LINKS: NavLink[] = [
  { href: "/", labelKey: "home", roles: ["member", "athlete"] },
  { href: "/schedule", labelKey: "schedule", roles: ["member"] },
  { href: "/my-workouts", labelKey: "myWorkouts", roles: ["athlete"] },
  { href: "/my-workouts/pantheon", labelKey: "pantheon", roles: ["athlete", "member"] },
  { href: "/account/billing", labelKey: "billing", roles: ["member", "athlete"] },
];

const ADMIN_NAV_LINKS: AdminNavLink[] = [
  { href: "/", labelKey: "home", mobileVisible: true },
  { href: "/admin/users", labelKey: "users", mobileVisible: false },
  { href: "/admin/finance", labelKey: "finance", mobileVisible: false },
  { href: "/admin/class-schedule", labelKey: "classes", mobileVisible: true },
  { href: "/admin/coaching-assignments", labelKey: "personalCoaching", mobileVisible: true },
  { href: "/admin/workouts", labelKey: "workouts", mobileVisible: false },
  { href: "/admin/metrics", labelKey: "analyticsMarketing", mobileVisible: false },
];

type DashboardCategory = {
  labelKey: string;
  items: { href: string; labelKey?: string; label?: string; description: string }[];
};

function pathActive(pathname: string, href: string) {
  if (href === "/admin") return pathname === "/admin";
  if (href === "/admin/metrics") {
    return ["/admin/metrics", "/admin/challenges", "/admin/reviews", "/admin/wellbeing"].some(
      (path) => pathname.startsWith(path),
    );
  }
  return pathname.startsWith(href);
}

function DashboardDropdown({ pathname }: { pathname: string }) {
  const i18n = useUiTranslations();
  const DASHBOARD_CATEGORIES: DashboardCategory[] = [
    {
      labelKey: "operations",
      items: [
        { href: "/admin/users", labelKey: "users", description: i18n("directoryAndPersonProfiles103196f") },
        { href: "/admin/finance", labelKey: "finance", description: i18n("invoicesPaymentsAndCredits3671159") },
        { href: "/admin/class-schedule", labelKey: "classes", description: i18n("slotsBookingsAndAttendanced9c2596") },
        { href: "/admin/coaching-assignments", labelKey: "personalCoaching", description: i18n("athleteProgrammingBoard954ac27") },
      ],
    },
    {
      labelKey: "contentGrowth",
      items: [
        { href: "/admin/workouts", labelKey: "workouts", description: i18n("masterWorkoutDefinitions09554e6") },
        { href: "/admin/metrics", labelKey: "analyticsMarketing", description: i18n("reportingEngagementAndGrowth37e1707") },
        { href: "/admin/challenges", label: i18n("challengesff38765"), description: i18n("seasonalEngagementCampaignsd11b07e") },
      ],
    },
    {
      labelKey: "utility",
      items: [
        { href: "/admin/settings", labelKey: "appConfigurations", description: i18n("appearanceRulesAndLevelTaxonomyc970499") },
      ],
    },
  ];

  const t = useTranslations("Navigation");
  const [open, setOpen] = useState(false);
  const [activeCategory, setActiveCategory] = useState<string | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  const isAdminActive = pathname === "/admin";
  const openMenu = () => {
    setOpen(true);
    setActiveCategory((current) => current ?? DASHBOARD_CATEGORIES[0]?.labelKey ?? null);
  };

  useEffect(() => {
    if (!open) return;
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
        setActiveCategory(null);
      }
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div ref={ref} className="relative shrink-0" onFocus={openMenu} onMouseEnter={openMenu}>
      <div
        className="flex items-center rounded-full"
        style={{ background: isAdminActive ? "var(--border)" : "transparent" }}
      >
        <Link
          href="/admin"
          className="whitespace-nowrap py-1 ps-2 text-xs font-semibold transition-colors sm:px-3 sm:text-sm"
          style={{ color: isAdminActive ? "var(--text)" : "var(--dim)" }}
        >
          {t("dashboard")}
        </Link>
        <button
          aria-expanded={open}
          aria-label={t("openDashboard")}
          className="px-1.5 py-1 text-xs sm:pe-2"
          style={{ color: isAdminActive ? "var(--text)" : "var(--dim)" }}
          onClick={() => setOpen((value) => !value)}
          type="button"
        >
          ▾
        </button>
      </div>

      {open ? (
        <div
          className="absolute start-0 top-full mt-1 flex max-w-[calc(100vw-1rem)] rounded-2xl shadow-[0_20px_60px_rgba(0,0,0,0.7)]"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", zIndex: 100 }}
          onMouseLeave={() => { setOpen(false); setActiveCategory(null); }}
        >
          {/* Category list */}
          <div className="w-32 border-e py-1.5 sm:w-40" style={{ borderColor: "var(--border)" }}>
            {DASHBOARD_CATEGORIES.map((cat) => (
              <button
                key={cat.labelKey}
                className="flex w-full items-center justify-between gap-2 px-4 py-2 text-start text-xs font-semibold transition-colors"
                style={{
                  color: activeCategory === cat.labelKey ? "var(--text)" : "var(--muted)",
                  background: activeCategory === cat.labelKey ? "color-mix(in srgb, var(--text) 5%, transparent)" : "transparent",
                }}
                onMouseEnter={() => setActiveCategory(cat.labelKey)}
                onClick={() => setActiveCategory(cat.labelKey)}
                type="button"
              >
                {t(cat.labelKey)}
                <span className="rtl:rotate-180" style={{ color: "var(--dim)" }}>›</span>
              </button>
            ))}
          </div>

          {/* Sub-items */}
          {activeCategory ? (
            <div className="w-48 py-1.5 sm:w-56">
              {DASHBOARD_CATEGORIES.find((c) => c.labelKey === activeCategory)?.items.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="block px-4 py-2.5 transition-colors hover:bg-[color-mix(in_srgb,var(--text)_4%,transparent)]"
                  onClick={() => { setOpen(false); setActiveCategory(null); }}
                >
                  <p className="text-sm font-semibold" style={{ color: pathname.startsWith(item.href) ? "var(--primary)" : "var(--text)" }}>
                    {item.labelKey ? t(item.labelKey) : item.label}
                  </p>
                  <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>{item.description}</p>
                </Link>
              ))}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

export function TopNav() {
  const i18n = useUiTranslations();
  const t = useTranslations("Navigation");
  const pathname = usePathname();
  const { status, tokens, currentUser, signOut } = useSession();
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const [msgOpen, setMsgOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser);

  const role = (currentUser?.role ?? "") as UserRole;
  const initials = currentUser?.nickname
    ? currentUser.nickname.slice(0, 2).toUpperCase()
    : "?";
  const avatarUrl = currentUser?.avatar_url ?? null;

  const financeQuery = useQuery({
    queryKey: ["my", "finance"],
    enabled: authenticated && role !== "admin",
    queryFn: () => fetchMyFinance(tokens!.access_token),
    staleTime: 2 * 60 * 1000,
  });
  const outstandingCents = financeQuery.data?.total_outstanding_balance_cents ?? 0;

  const unreadQuery = useQuery({
    queryKey: ["messages", "unread"],
    enabled: authenticated,
    queryFn: () => fetchUnreadCount(tokens!.access_token),
    staleTime: 15 * 1000,
  });
  const unreadCount = unreadQuery.data?.unread_count ?? 0;

  // Chat delivery records notify recipients only. The event refreshes the
  // Messages badge without exposing the delivery record in Notifications.
  useEffect(() => {
    if (!tokens?.access_token || !currentUser?.id) return;
    return subscribeToTopic(tokens.access_token, `notifications:${currentUser.id}`, {
      "notifications:changed": () => {
        void queryClient.invalidateQueries({ queryKey: ["messages", "unread"] });
      },
    });
  }, [tokens?.access_token, currentUser?.id, queryClient]);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    }
    if (menuOpen) document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [menuOpen]);

  if (CANVAS_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    return null;
  }

  if (!currentUser) return null;

  return (
    <header
      className="sticky top-0 z-50 flex items-center"
      style={{
        background: "var(--bg)",
        borderBottom: "1px solid var(--border)",
        height: "3.25rem",
      }}
    >
      <div className="flex w-full items-center gap-2 px-2 sm:gap-4 sm:px-5">
        <Link
          href="/"
          className="hidden shrink-0 text-xs font-bold uppercase tracking-[0.28em] sm:block"
          style={{ color: "var(--text)" }}
        >
          {i18n("milose9defa8")}
        </Link>

        <nav className="flex min-w-0 flex-1 items-center gap-0.5 overflow-visible sm:gap-1">
          {role === "admin" ? <DashboardDropdown pathname={pathname} /> : null}
          <div className="flex min-w-0 items-center gap-0.5 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden sm:gap-1">
            {role === "admin"
              ? ADMIN_NAV_LINKS.map((link) => {
                  const active = pathActive(pathname, link.href);
                  return (
                    <Link
                      key={link.href}
                      href={link.href}
                      className={(link.mobileVisible ? "" : "hidden md:block") + " whitespace-nowrap rounded-full px-2 py-1 text-xs font-semibold transition-colors sm:px-3 sm:text-sm"}
                      style={{
                        background: active ? "var(--border)" : "transparent",
                        color: active ? "var(--text)" : "var(--dim)",
                      }}
                    >
                      {t(link.labelKey)}
                    </Link>
                  );
                })
              : null}
            {NAV_LINKS.filter((link) => link.roles.includes(role)).map((link) => {
              const active = pathActive(pathname, link.href);
              const showBalanceBadge = link.href === "/account/billing" && outstandingCents > 0;
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className="relative whitespace-nowrap rounded-full px-2 py-1 text-xs font-semibold transition-colors sm:px-3 sm:text-sm"
                  style={{
                    background: active ? "var(--border)" : "transparent",
                    color: active ? "var(--text)" : "var(--dim)",
                  }}
                >
                  {t(link.labelKey)}
                  {showBalanceBadge ? (
                    <span
                      className="absolute -end-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] font-bold"
                      style={{ background: "var(--danger)", color: "#fff" }}
                    >
                      !
                    </span>
                  ) : null}
                </Link>
              );
            })}
          </div>
        </nav>

        <div className="ms-auto flex shrink-0 items-center gap-1 sm:gap-2">
          <NotificationBell />

          <div className="relative shrink-0">
            <button
              type="button"
              className="relative whitespace-nowrap rounded-full px-2 py-1 text-xs font-semibold transition-colors sm:px-3 sm:text-sm"
              style={{
                background: msgOpen ? "var(--border)" : "transparent",
                color: msgOpen ? "var(--text)" : "var(--dim)",
              }}
              onClick={() => setMsgOpen((value) => !value)}
            >
              {t("chat")}
              {unreadCount > 0 ? (
                <span
                  className="absolute -end-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] font-bold"
                  style={{ background: "var(--primary)", color: "var(--bg)" }}
                >
                  {unreadCount > 99 ? "99+" : unreadCount}
                </span>
              ) : null}
            </button>
            {msgOpen ? <DirectMessagesPanel onClose={() => setMsgOpen(false)} /> : null}
          </div>

          <div ref={menuRef} className="relative shrink-0">
            <button
              className="flex items-center gap-2 rounded-full py-1 ps-1 pe-3 text-sm font-semibold transition-colors"
              style={{ background: "var(--panel)", color: "var(--text)" }}
              onClick={() => setMenuOpen((value) => !value)}
              type="button"
            >
              {avatarUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={avatarUrl}
                  alt={currentUser.nickname}
                  className="h-7 w-7 rounded-full object-cover"
                />
              ) : (
                <span
                  className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold"
                  style={{ background: "var(--primary)", color: "var(--bg)" }}
                >
                  {initials}
                </span>
              )}
              <span className="hidden max-w-[7rem] truncate sm:block" style={{ color: "var(--text-soft)" }}>
                {currentUser.nickname}
              </span>
              <span className="text-[10px]" style={{ color: "var(--dim)" }}>
                ▾
              </span>
            </button>

            {menuOpen ? (
              <div
                className="absolute end-0 top-full mt-2 w-44 overflow-hidden rounded-2xl py-1 shadow-[0_16px_60px_rgba(0,0,0,0.6)]"
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              >
                <div className="border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
                  <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                    {i18n("signedInAsa02107c")}
                  </p>
                  <p className="mt-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {currentUser.nickname}
                  </p>
                  <p className="mt-0.5 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    <SemanticLabel value={currentUser.role} />
                  </p>
                </div>
                <Link
                  href="/profile"
                  className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                  style={{ color: "var(--text-soft)" }}
                  onClick={() => setMenuOpen(false)}
                >
                  {t("profile")}
                </Link>
                {role !== "admin" ? (
                  <Link
                    href="/account/billing"
                    className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                    style={{ color: "var(--text-soft)" }}
                    onClick={() => setMenuOpen(false)}
                  >
                    {t("billing")}
                  </Link>
                ) : null}
                <button
                  className="w-full px-4 py-2.5 text-start text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                  style={{ color: "var(--primary)" }}
                  onClick={() => {
                    signOut();
                    setMenuOpen(false);
                  }}
                  type="button"
                >
                  {i18n("signOutdc1649a")}
                </button>
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </header>
  );
}
