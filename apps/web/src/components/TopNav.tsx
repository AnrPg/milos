"use client";

import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
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
import {
  activeItemId,
  can,
  clientRole,
  hasStaffRole,
  sectionGroupFor,
  staffNavItems,
} from "@/lib/role-navigation";
import { setView, useView } from "@/lib/view-mode";
import { PriorityNav } from "@/components/nav/PriorityNav";
import { SectionTabs } from "@/components/nav/SectionTabs";
import { MobileNavMenu } from "@/components/nav/MobileNavMenu";
import { openNotifications } from "@/components/notifications/NotificationBell";
import { SemanticLabel } from "@/components/semantic-label";
import { entitledFeatures } from "@/components/client/entitlement";
import { useClientEntitlement } from "@/components/client/use-client-entitlement";
import { OrganizationSelector } from "@/components/organization-selector";

export { adminHref } from "@/lib/organization-slug";

// The public box page draws its own header over the cover (ADR-142).
const CANVAS_PATHS = ["/login", "/b"];

type OrganizationMembershipSummary = {
  organization: { name: string; slug: string };
  settings?: { brand_name?: string | null; brand_logo_url?: string | null } | null;
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

/** ADR-121: the selected tenant's logo for the shell header, if any. */
export function tenantBrandLogoUrl(
  memberships: OrganizationMembershipSummary[],
  selectedSlug?: string | null,
) {
  const selectedMembership =
    selectedSlug ? memberships.find((entry) => entry.organization.slug === selectedSlug) : null;
  const membership = selectedMembership ?? memberships[0];

  return membership?.settings?.brand_logo_url?.trim() || null;
}

export function TopNav() {
  const i18n = useUiTranslations();
  const t = useTranslations("Navigation");
  const pathname = usePathname();
  const router = useRouter();
  const view = useView();
  const { status, tokens, currentUser, signOut } = useSession();
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const [msgOpen, setMsgOpen] = useState(false);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
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
  const role = surfaceRoleForMembership(currentMembership, view);
  const canSwitchView =
    hasStaffRole(currentMembership) &&
    clientRole(currentMembership) !== null &&
    surfaceRoleForMembership(currentMembership, "staff") === "admin";
  const showSelfServiceSurfaces =
    role !== "admin" && Boolean(currentUser) && showsTenantSelfServiceSurfaces(currentUser);
  const financeQuery = useQuery({
    queryKey: ["my", "finance"],
    enabled: authenticated && showSelfServiceSurfaces,
    queryFn: () => fetchMyFinance(tokens!.access_token),
    staleTime: 2 * 60 * 1000,
  });
  const outstandingCents = financeQuery.data?.total_outstanding_balance_cents ?? 0;
  const { entitlement } = useClientEntitlement(authenticated && showSelfServiceSurfaces);
  const features = entitledFeatures(entitlement);
  const staffItems = role === "admin" ? staffNavItems(currentMembership) : [];
  // Members and athletes navigate with the fixed bottom bar (ADR-137); the
  // top bar keeps brand, notifications, messages and the account menu.
  const navItems = role === "admin" ? staffItems : [];
  const hrefFor = (href: string, scoped?: boolean) => (scoped ? adminHref(href, selectedOrganizationSlug) : href);
  const navLinks = navItems.map((item) => ({ id: item.id, href: hrefFor(item.href, item.scoped), label: t(item.labelKey) }));
  const activeNavId = activeItemId(pathname, navItems);
  const sectionGroup = sectionGroupFor(pathname, { surface: role, staffItems, features });

  const brandName = tenantBrandName(memberships, selectedOrganizationSlug) ?? i18n("milosTraining5b1a1c1");
  const brandLogoUrl = tenantBrandLogoUrl(memberships, selectedOrganizationSlug);
  const hasTenantMembership = memberships.length > 0;
  const showTenantShell = hasTenantMembership;
  const mobileLinks = isVendor
    ? [{ id: "platform", href: "/platform/organizations", label: t("platform") }, ...(showTenantShell ? navLinks : [])]
    : navLinks;
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
      className="sticky top-0 z-50 flex flex-col overflow-x-clip"
      style={{
        background: "var(--bg)",
        borderBottom: "1px solid var(--border)",
        minHeight: "3.25rem",
      }}
    >
      <div className="flex w-full items-center gap-2 px-2 py-1 sm:flex-wrap sm:gap-x-4 sm:px-5">
        {(showTenantShell && mobileLinks.length > 0) || isVendor ? (
          <MobileNavMenu links={mobileLinks} activeId={activeNavId} label={t("menu")} />
        ) : null}
        <Link
          href="/"
          className="col-span-2 flex min-w-0 items-center gap-2 whitespace-normal break-words text-xs font-bold uppercase leading-tight sm:col-span-1 sm:max-w-[32rem] sm:shrink-0"
          style={{ color: "var(--text)" }}
          title={brandName}
        >
          {brandLogoUrl ? (
            <Image
              alt=""
              aria-hidden="true"
              className="h-7 w-7 shrink-0 rounded-md object-contain"
              height={28}
              src={brandLogoUrl}
              unoptimized
              width={28}
            />
          ) : null}
          <span className="min-w-0">{brandName}</span>
        </Link>

        <nav className="hidden min-w-0 flex-1 items-center gap-1 overflow-visible sm:flex">
          {isVendor ? (
            <Link
              href="/platform/organizations"
              className="whitespace-nowrap rounded-full px-3 py-1 text-sm font-semibold transition-colors"
              style={{
                background: pathActive(pathname, "/platform") ? "var(--border)" : "transparent",
                color: pathActive(pathname, "/platform") ? "var(--text)" : "var(--dim)",
              }}
            >
              {t("platform")}
            </Link>
          ) : null}
          {showTenantShell && navLinks.length > 0 ? (
            <PriorityNav links={navLinks} activeId={activeNavId} moreLabel={t("more")} />
          ) : null}
        </nav>

        <div className="ms-auto flex shrink-0 items-center gap-1 sm:gap-2">
          {/* Phones open notifications from the avatar menu (ADR-103). */}
          {/* Mounted for every signed-in account: ♡ in the Feed opens it too (ADR-142). */}
          <NotificationBell onUnreadChange={setUnreadNotifications} triggerClassName={`hidden ${showTenantShell ? "sm:flex" : ""}`} />

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
              className="relative flex items-center gap-2 rounded-full py-1 ps-1 pe-3 text-sm font-semibold transition-colors"
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
              <span className="relative text-[10px]" style={{ color: "var(--dim)" }}>
                ▾
                {role !== "admin" && outstandingCents > 0 ? (
                  <span aria-hidden="true" className="absolute -end-1.5 -top-1.5 h-2 w-2 rounded-full" style={{ background: "var(--danger)" }} />
                ) : null}
              </span>
              {unreadNotifications > 0 ? (
                <span
                  aria-label={t("unreadNotifications", { count: unreadNotifications })}
                  className="absolute -end-0.5 -top-0.5 h-3 w-3 rounded-full sm:hidden"
                  style={{ background: "var(--danger)", border: "2px solid var(--bg)" }}
                />
              ) : null}
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
                {showTenantShell ? (
                  <button
                    type="button"
                    className="flex w-full items-center justify-between gap-2 px-4 py-2.5 text-start text-sm font-semibold transition-colors hover:bg-[var(--border)] sm:hidden"
                    style={{ color: "var(--text-soft)" }}
                    onClick={() => {
                      setMenuOpen(false);
                      openNotifications();
                    }}
                  >
                    {t("notifications")}
                    {unreadNotifications > 0 ? (
                      <span className="rounded-full px-1.5 text-[10px] font-bold" style={{ background: "var(--danger)", color: "#fff" }}>
                        {unreadNotifications > 99 ? "99+" : unreadNotifications}
                      </span>
                    ) : null}
                  </button>
                ) : null}
                <Link
                  href="/me/settings"
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
                    {role === "admin" && can(currentMembership, "manage_settings") ? (
                      <Link
                        href={adminHref("/admin/settings", selectedOrganizationSlug)}
                        className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                        style={{ color: "var(--text-soft)" }}
                        onClick={() => setMenuOpen(false)}
                      >
                        {t("settings")}
                      </Link>
                    ) : null}
                    {canSwitchView ? (
                      <button
                        type="button"
                        className="block w-full px-4 py-2.5 text-start text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                        style={{ color: "var(--text-soft)" }}
                        onClick={() => {
                          const next = role === "admin" ? "client" : "staff";
                          setView(next);
                          setMenuOpen(false);
                          router.push(next === "client" ? "/" : adminHref("/admin", selectedOrganizationSlug));
                        }}
                      >
                        {role === "admin" ? t("myTraining") : t("staffView")}
                      </button>
                    ) : null}
                    {role !== "admin" && showSelfServiceSurfaces ? (
                      <Link
                        href="/me/payments"
                        className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                        style={{ color: "var(--text-soft)" }}
                        onClick={() => setMenuOpen(false)}
                      >
                        <span className="flex items-center justify-between gap-2">
                          {t("billing")}
                          {outstandingCents > 0 ? (
                            <span className="rounded-full px-1.5 text-[10px] font-bold" style={{ background: "var(--danger)", color: "#fff" }}>
                              !
                            </span>
                          ) : null}
                        </span>
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
      {showTenantShell && sectionGroup ? (
        <SectionTabs group={sectionGroup} pathname={pathname} hrefFor={hrefFor} labelFor={(key) => t(key)} />
      ) : null}
    </header>
  );
}
