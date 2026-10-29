"use client";

import { PaleeMark } from "@/components/branding/PaleeMark";
import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BODY_SETTINGS_KEY, fetchBodySettings } from "@/api/body";
import { fetchMyFinance } from "@/api/my-finance";
import { PASSWORD_RESETS_KEY } from "@/api/password-resets";
import { gymUnreadKey, useGymUnreadCount } from "@/components/chat/use-messages-unread";
import { usePasswordResetsInbox } from "@/components/member-app/me/use-password-resets";
import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";
import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";
import { adminHref, membershipWorkspaceHref, rememberSelectedOrganization, useOrganizationSlug } from "@/lib/organization-slug";
import { selectedMembership, surfaceRoleForMembership, useOrganizationMemberships } from "@/lib/membership-role";
import {
  activeItemId,
  can,
  hasStaffRole,
  sectionGroupFor,
  staffNavItems,
} from "@/lib/role-navigation";
import { setView, useView } from "@/lib/view-mode";
import { PriorityNav } from "@/components/nav/PriorityNav";
import { SectionTabs } from "@/components/nav/SectionTabs";
import { MobileNavMenu } from "@/components/nav/MobileNavMenu";
import { useMemberShell } from "@/components/nav/BottomNav";
import { MemberTopBar } from "@/components/nav/MemberTopBar";
import { NavIcon } from "@/components/nav/NavIcons";
import { openNotifications } from "@/components/notifications/NotificationBell";
import { SemanticLabel } from "@/components/semantic-label";
import { entitledFeatures } from "@/components/client/entitlement";
import { useClientEntitlement } from "@/components/client/use-client-entitlement";
import { OrganizationSelector } from "@/components/organization-selector";
import { Popover } from "@/components/ui/Popover";
import { ProfileSwitcherMenu } from "@/components/account/ProfileSwitcherMenu";

export { adminHref } from "@/lib/organization-slug";

// The public box page draws its own header over the cover (ADR-142).
const CANVAS_PATHS = ["/login", "/b"];
// Screens that fill the whole display (ADR-155): the door kiosk and the printed poster.
const CANVAS_PATTERNS = [/^\/admin\/check-in\/(?:door|poster)\/[^/]+\/?$/];

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
  const tResets = useTranslations("passwordResets");
  const pathname = usePathname();
  const router = useRouter();
  const view = useView();
  const { status, tokens, currentUser, signOut } = useSession();
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const [msgOpen, setMsgOpen] = useState(false);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const menuButtonRef = useRef<HTMLButtonElement>(null);
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser);

  const isVendor = Boolean(currentUser?.vendor);
  const initials = currentUser?.nickname
    ? currentUser.nickname.slice(0, 2).toUpperCase()
    : "?";
  const avatarUrl = currentUser?.avatar_url ?? null;

  const membershipsQuery = useOrganizationMemberships();
  const memberShell = useMemberShell();
  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];
  const selectedOrganizationSlug = useOrganizationSlug();
  const currentMembership = selectedMembership(memberships, selectedOrganizationSlug);
  const role = surfaceRoleForMembership(currentMembership, view);
  // ADR-103 (amended): every staff member can switch the console to the social app.
  const canSwitchView = role === "admin" && hasStaffRole(currentMembership);
  const openSocialApp = () => {
    setView("client");
    router.push("/");
  };
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
  // Ρυθμίσεις › Σώμα can switch the Σώμα and Ευεξία segments off (ADR-158 §7).
  const onJournal = role !== "admin" && stripOrganizationPrefix(pathname).startsWith("/journal");
  const bodySettingsQuery = useQuery({
    queryKey: BODY_SETTINGS_KEY,
    enabled: authenticated && onJournal,
    queryFn: () => fetchBodySettings(tokens!.access_token),
    staleTime: 5 * 60_000,
  });
  const sectionGroup = sectionGroupFor(pathname, {
    surface: role,
    staffItems,
    features,
    journalSections: bodySettingsQuery.data?.settings?.journal_sections ?? null,
  });

  const brandName = tenantBrandName(memberships, selectedOrganizationSlug) ?? i18n("brandName");
  const brandLogoUrl = tenantBrandLogoUrl(memberships, selectedOrganizationSlug);
  const hasTenantMembership = memberships.length > 0;
  const showTenantShell = hasTenantMembership;
  const mobileLinks = isVendor
    ? [{ id: "platform", href: "/platform/organizations", label: t("platform") }, ...(showTenantShell ? navLinks : [])]
    : navLinks;
  const unreadQuery = useGymUnreadCount(authenticated && showTenantShell);
  const unreadCount = unreadQuery.data?.unread_count ?? 0;
  // ADR-187: handlers (vendor, staff, coaches) reach the password reset
  // requests from the account menu, while there are any (the vendor always).
  const resetsQuery = usePasswordResetsInbox();
  const resetRequests = resetsQuery.data?.requests ?? [];
  const resetsToAct = resetRequests.filter((request) => ["open", "mine", "expired"].includes(request.state)).length;

  // Chat delivery records notify recipients only. The event refreshes the
  // Messages badge without exposing the delivery record in Notifications,
  // and the resets inbox (a new request notifies its handlers). A rejoin
  // after a dropped connection resyncs both, since events may have been missed.
  useEffect(() => {
    if (!tokens?.access_token || !currentUser?.id) return;
    const refresh = () => {
      void queryClient.invalidateQueries({ queryKey: gymUnreadKey(selectedOrganizationSlug) });
      void queryClient.invalidateQueries({ queryKey: PASSWORD_RESETS_KEY });
    };
    return subscribeToTopic(tokens.access_token, `notifications:${currentUser.id}`, { "notifications:changed": refresh }, { onRejoin: refresh });
  }, [tokens?.access_token, currentUser?.id, queryClient, selectedOrganizationSlug]);

  if (
    CANVAS_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/")) ||
    CANVAS_PATTERNS.some((pattern) => pattern.test(stripOrganizationPrefix(pathname)))
  ) {
    return null;
  }

  if (!currentUser) return null;

  // Members and athletes navigate with the floating bottom bar and the member
  // top bar instead (components/nav/BottomNav.tsx, MemberTopBar.tsx): the
  // logo and the bell on top, the page group's tab strip under them, the
  // account menu's links in Εγώ. Vendors keep this bar for the platform console.
  if ((memberShell && !isVendor) || membershipsQuery.isLoading) {
    return (
      <>
        <NotificationBell onUnreadChange={setUnreadNotifications} hideTrigger />
        {memberShell ? (
          <MemberTopBar>
            {sectionGroup ? <SectionTabs group={sectionGroup} pathname={pathname} hrefFor={hrefFor} labelFor={(key) => t(key)} /> : null}
          </MemberTopBar>
        ) : null}
      </>
    );
  }

  return (
    <header
      className="sticky top-0 z-(--z-nav) flex flex-col overflow-x-clip"
      style={{
        // ADR-171: below the status bar inside the store apps (0 on the web).
        top: "var(--safe-top, 0px)",
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
          ) : (
            <PaleeMark className="h-6 w-6 shrink-0" />
          )}
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
          {/* «Social»: from the console to the social app, always in sight. */}
          {canSwitchView ? (
            <button
              type="button"
              onClick={openSocialApp}
              className="flex min-h-8 shrink-0 items-center gap-1.5 rounded-full px-2.5 text-xs font-bold outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] sm:px-3 sm:text-sm"
              style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary-strong)" }}
              aria-label={t("socialApp")}
            >
              <NavIcon name="feed" size={16} strokeWidth={2} />
              <span className="hidden min-[400px]:inline">{t("socialApp")}</span>
            </button>
          ) : null}
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
                <NavIcon name="messages" size={16} strokeWidth={2} className="sm:hidden" />
                <span className="hidden sm:inline">{t("chat")}</span>
                {unreadCount > 0 ? (
                  <span
                    className="absolute -end-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] font-bold"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  >
                    {unreadCount > 99 ? "99+" : unreadCount}
                  </span>
                ) : null}
              </button>
              {msgOpen ? <DirectMessagesPanel onClose={() => setMsgOpen(false)} /> : null}
            </div>
          ) : null}

          <div className="relative shrink-0">
            <button
              ref={menuButtonRef}
              aria-haspopup="menu"
              aria-expanded={menuOpen}
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
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
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

            <Popover
              anchorRef={menuButtonRef}
              open={menuOpen}
              onClose={() => setMenuOpen(false)}
              align="end"
              width={(currentUser.profile_count ?? 1) > 1 ? 224 : 176}
              className="rounded-2xl py-1 shadow-[var(--shadow-lg)]"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
                <div className="border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
                  <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                    {i18n("signedInAsa02107c")}
                  </p>
                  <p className="mt-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {currentUser.nickname}
                  </p>
                  {currentUser.handle && currentUser.handle !== currentUser.nickname ? (
                    <p className="truncate text-xs" style={{ color: "var(--dim)" }} dir="ltr">
                      @{currentUser.handle}
                    </p>
                  ) : null}
                  <p className="mt-0.5 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {isVendor ? t("platform") : <SemanticLabel value={currentMembership?.role ?? currentUser.role} />}
                  </p>
                </div>
                <ProfileSwitcherMenu />
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
                      <span className="rounded-full px-1.5 text-[10px] font-bold" style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>
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
                {resetRequests.length > 0 || isVendor ? (
                  <Link
                    href="/password-resets"
                    className="flex items-center justify-between gap-2 px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                    style={{ color: "var(--text-soft)" }}
                    onClick={() => setMenuOpen(false)}
                  >
                    {tResets("navLink")}
                    {resetsToAct > 0 ? (
                      <span className="rounded-full px-1.5 text-[10px] font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                        {resetsToAct > 99 ? "99+" : resetsToAct}
                      </span>
                    ) : null}
                  </Link>
                ) : null}
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
                    {role === "admin" && (can(currentMembership, "manage_settings") || can(currentMembership, "manage_locations")) ? (
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
                          setMenuOpen(false);
                          openSocialApp();
                        }}
                      >
                        {t("socialApp")}
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
                            <span className="rounded-full px-1.5 text-[10px] font-bold" style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>
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
            </Popover>
          </div>
        </div>
      </div>
      {showTenantShell && sectionGroup ? (
        <SectionTabs group={sectionGroup} pathname={pathname} hrefFor={hrefFor} labelFor={(key) => t(key)} />
      ) : null}
    </header>
  );
}
