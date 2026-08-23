"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchMyFinance } from "@/api/my-finance";
import { fetchUnreadCount } from "@/api/messaging";
import { fetchOrganizationMemberships } from "@/api/organizations";
import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";
import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";
import { adminHref, membershipWorkspaceHref, rememberSelectedOrganization, useOrganizationSlug } from "@/lib/organization-slug";
import { selectedMembership, surfaceRoleForMembership } from "@/lib/membership-role";
import { SemanticLabel } from "@/components/semantic-label";
import { OrganizationSelector } from "@/components/organization-selector";

export { adminHref } from "@/lib/organization-slug";

const CANVAS_PATHS = ["/login"];

type UserRole = "member" | "athlete" | "admin";

type NavLink = { href: string; labelKey: string; roles: UserRole[] };
type AdminNavLink = { href: string; labelKey: string; mobileVisible: boolean };
type OrganizationMembershipSummary = {
  organization: { name: string; slug: string };
  settings?: { brand_name?: string | null } | null;
};

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

const ADMIN_NAV_ICONS: Record<string, string> = {
  "/": "⌂",
  "/admin/users": "◎",
  "/admin/finance": "$",
  "/admin/class-schedule": "▦",
  "/admin/coaching-assignments": "◇",
  "/admin/workouts": "▣",
  "/admin/metrics": "⌁",
};

const MEMBER_NAV_ICONS: Record<string, string> = {
  "/": "⌂",
  "/schedule": "▦",
  "/my-workouts": "▣",
  "/my-workouts/pantheon": "★",
  "/account/billing": "$",
};

function stripOrganizationPrefix(pathname: string) {
  return pathname.replace(/^\/org\/[^/]+(?=\/|$)/, "") || "/";
}

export function pathActive(pathname: string, href: string) {
  const relativePathname = stripOrganizationPrefix(pathname);
  const relativeHref = stripOrganizationPrefix(href);

  if (relativeHref === "/") return relativePathname === "/";
  if (relativeHref === "/admin") return relativePathname === "/admin";
  if (relativeHref === "/admin/metrics") {
    return ["/admin/metrics", "/admin/challenges", "/admin/reviews", "/admin/wellbeing"].some(
      (path) => relativePathname.startsWith(path),
    );
  }
  return relativePathname.startsWith(relativeHref);
}

export function tenantBrandName(
  memberships: OrganizationMembershipSummary[],
  selectedSlug?: string | null,
) {
  const selectedMembership =
    selectedSlug ? memberships.find((entry) => entry.organization.slug === selectedSlug) : null;
  const membership = selectedMembership ?? memberships[0];

  return membership?.settings?.brand_name?.trim() || membership?.organization.name.trim() || null;
}

function DashboardDropdown({
  pathname,
  organizationSlug,
}: {
  pathname: string;
  organizationSlug: string | null;
}) {
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

  const isAdminActive = stripOrganizationPrefix(pathname) === "/admin";
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
          href={adminHref("/admin", organizationSlug)}
          className="grid h-8 min-w-8 place-items-center rounded-full px-2 text-xs font-semibold transition-colors sm:h-auto sm:min-w-0 sm:px-3 sm:py-1 sm:text-sm"
          style={{ color: isAdminActive ? "var(--text)" : "var(--dim)" }}
          aria-label={t("dashboard")}
          title={t("dashboard")}
        >
          <span aria-hidden="true" className="sm:hidden">⌂</span>
          <span className="hidden sm:inline">{t("dashboard")}</span>
        </Link>
        <button
          aria-expanded={open}
          aria-label={t("openDashboard")}
          className="h-8 px-1.5 text-xs sm:h-auto sm:py-1 sm:pe-2"
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
                  href={adminHref(item.href, organizationSlug)}
                  className="block px-4 py-2.5 transition-colors hover:bg-[color-mix(in_srgb,var(--text)_4%,transparent)]"
                  onClick={() => { setOpen(false); setActiveCategory(null); }}
                >
                  <p className="text-sm font-semibold" style={{ color: pathActive(pathname, item.href) ? "var(--primary)" : "var(--text)" }}>
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

  const isVendor = Boolean(currentUser?.vendor);
  const initials = currentUser?.nickname
    ? currentUser.nickname.slice(0, 2).toUpperCase()
    : "?";
  const avatarUrl = currentUser?.avatar_url ?? null;

  const membershipsQuery = useQuery({
    queryKey: ["organization-memberships", tokens?.access_token],
    enabled: authenticated,
    queryFn: () => fetchOrganizationMemberships(tokens!.access_token),
    staleTime: 60_000,
  });
  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];
  const selectedOrganizationSlug = useOrganizationSlug();
  const currentMembership = selectedMembership(memberships, selectedOrganizationSlug);
  const role = surfaceRoleForMembership(currentMembership) as UserRole;
  const showSelfServiceSurfaces =
    role !== "admin" && Boolean(currentUser) && showsTenantSelfServiceSurfaces(currentUser);
  const financeQuery = useQuery({
    queryKey: ["my", "finance"],
    enabled: authenticated && showSelfServiceSurfaces,
    queryFn: () => fetchMyFinance(tokens!.access_token),
    staleTime: 2 * 60 * 1000,
  });
  const outstandingCents = financeQuery.data?.total_outstanding_balance_cents ?? 0;

  const brandName = tenantBrandName(memberships, selectedOrganizationSlug) ?? i18n("milosTraining5b1a1c1");
  const hasTenantMembership = memberships.length > 0;
  const showTenantShell = hasTenantMembership;
  const unreadQuery = useQuery({
    queryKey: ["messages", "unread", selectedOrganizationSlug],
    enabled: authenticated && showTenantShell && Boolean(selectedOrganizationSlug),
    queryFn: () => fetchUnreadCount(tokens!.access_token, selectedOrganizationSlug),
    staleTime: 15 * 1000,
  });
  const unreadCount = unreadQuery.data?.unread_count ?? 0;

  // Chat delivery records notify recipients only. The event refreshes the
  // Messages badge without exposing the delivery record in Notifications.
  useEffect(() => {
    if (!tokens?.access_token || !currentUser?.id) return;
    return subscribeToTopic(tokens.access_token, `notifications:${currentUser.id}`, {
      "notifications:changed": () => {
        void queryClient.invalidateQueries({ queryKey: ["messages", "unread", selectedOrganizationSlug] });
      },
    });
  }, [tokens?.access_token, currentUser?.id, queryClient, selectedOrganizationSlug]);

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
      className="sticky top-0 z-50 flex items-center overflow-x-clip"
      style={{
        background: "var(--bg)",
        borderBottom: "1px solid var(--border)",
        minHeight: "3.25rem",
      }}
    >
      <div className="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-x-2 gap-y-1 px-2 py-1 sm:flex sm:flex-wrap sm:gap-x-4 sm:px-5">
        <Link
          href="/"
          className="block min-w-0 truncate text-xs font-bold uppercase sm:max-w-[32rem] sm:shrink-0 sm:whitespace-normal sm:break-words"
          style={{ color: "var(--text)" }}
          title={brandName}
        >
          {brandName}
        </Link>

        <nav className="order-3 col-span-2 flex min-w-0 flex-1 flex-wrap items-center gap-0.5 overflow-visible sm:order-none sm:col-span-1 sm:gap-1">
          {isVendor ? (
            <Link
              href="/platform/organizations"
              className="whitespace-nowrap rounded-full px-2 py-1 text-xs font-semibold transition-colors sm:px-3 sm:text-sm"
              style={{
                background: pathActive(pathname, "/platform") ? "var(--border)" : "transparent",
                color: pathActive(pathname, "/platform") ? "var(--text)" : "var(--dim)",
              }}
            >
              {t("platform")}
            </Link>
          ) : null}
          {showTenantShell && role === "admin" ? (
            <DashboardDropdown pathname={pathname} organizationSlug={selectedOrganizationSlug} />
          ) : null}
          <div className="flex min-w-0 flex-wrap items-center gap-0.5 overflow-visible sm:gap-1">
            {showTenantShell && role === "admin"
              ? ADMIN_NAV_LINKS.map((link) => {
                  const active = pathActive(pathname, link.href);
                  const icon = ADMIN_NAV_ICONS[link.href] ?? "•";
                  return (
                    <Link
                      key={link.href}
                      href={adminHref(link.href, selectedOrganizationSlug)}
                      className={(link.mobileVisible ? "" : "hidden md:block") + " grid h-8 min-w-8 place-items-center rounded-full px-2 text-xs font-semibold transition-colors sm:h-auto sm:min-w-0 sm:px-3 sm:py-1 sm:text-sm"}
                      style={{
                        background: active ? "var(--border)" : "transparent",
                        color: active ? "var(--text)" : "var(--dim)",
                      }}
                      aria-label={t(link.labelKey)}
                      title={t(link.labelKey)}
                    >
                      <span aria-hidden="true" className="sm:hidden">{icon}</span>
                      <span className="hidden sm:inline">{t(link.labelKey)}</span>
                    </Link>
                  );
                })
              : null}
            {showTenantShell && showSelfServiceSurfaces && NAV_LINKS.filter((link) => link.roles.includes(role)).map((link) => {
              const active = pathActive(pathname, link.href);
              const showBalanceBadge = link.href === "/account/billing" && outstandingCents > 0;
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className="relative grid h-8 min-w-8 place-items-center rounded-full px-2 text-xs font-semibold transition-colors sm:h-auto sm:min-w-0 sm:px-3 sm:py-1 sm:text-sm"
                  style={{
                    background: active ? "var(--border)" : "transparent",
                    color: active ? "var(--text)" : "var(--dim)",
                  }}
                  aria-label={t(link.labelKey)}
                  title={t(link.labelKey)}
                >
                  <span aria-hidden="true" className="sm:hidden">{MEMBER_NAV_ICONS[link.href] ?? "•"}</span>
                  <span className="hidden sm:inline">{t(link.labelKey)}</span>
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
          {showTenantShell ? <NotificationBell /> : null}

          {showTenantShell ? (
            <div className="relative shrink-0">
              <button
                type="button"
                className="relative grid h-8 min-w-8 place-items-center rounded-full px-2 text-xs font-semibold transition-colors sm:h-auto sm:min-w-0 sm:px-3 sm:py-1 sm:text-sm"
                style={{
                  background: msgOpen ? "var(--border)" : "transparent",
                  color: msgOpen ? "var(--text)" : "var(--dim)",
                }}
                onClick={() => setMsgOpen((value) => !value)}
                aria-label={t("chat")}
                title={t("chat")}
              >
                <span aria-hidden="true" className="sm:hidden">✉</span>
                <span className="hidden sm:inline">{t("chat")}</span>
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
          ) : null}

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
                    {isVendor ? t("platform") : <SemanticLabel value={currentMembership?.role ?? currentUser.role} />}
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
                {isVendor ? (
                  <>
                    <Link
                      href="/platform/organizations"
                      className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                      style={{ color: "var(--text-soft)" }}
                      onClick={() => setMenuOpen(false)}
                    >
                      {t("platform")}
                    </Link>
                    {memberships.length > 0 ? (
                      <div className="border-t px-4 py-2.5" style={{ borderColor: "var(--border)" }}>
                        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                          {i18n("yourOrganizations")}
                        </p>
                        <div className="mt-1.5 space-y-1">
                          {memberships.map((membership) => (
                            <Link
                              key={membership.id}
                              href={membershipWorkspaceHref(membership)}
                              onClick={() => {
                                rememberSelectedOrganization(membership.organization.slug);
                                setMenuOpen(false);
                              }}
                              className="block truncate text-sm font-semibold transition-colors hover:opacity-80"
                              style={{ color: "var(--text-soft)" }}
                            >
                              {membership.organization.name}
                            </Link>
                          ))}
                        </div>
                      </div>
                    ) : null}
                  </>
                ) : (
                  <>
                    <OrganizationSelector variant="menu" onSelect={() => setMenuOpen(false)} />
                    {role !== "admin" && showSelfServiceSurfaces ? (
                      <Link
                        href="/account/billing"
                        className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                        style={{ color: "var(--text-soft)" }}
                        onClick={() => setMenuOpen(false)}
                      >
                        {t("billing")}
                      </Link>
                    ) : null}
                  </>
                )}
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
