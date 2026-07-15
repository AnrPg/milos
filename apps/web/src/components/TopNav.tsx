"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchMyFinance } from "@/api/my-finance";
import { fetchUnreadCount } from "@/api/messaging";
import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";

const CANVAS_PATHS = ["/admin/workouts/new", "/login"];

type UserRole = "member" | "athlete" | "admin";

type NavLink = { href: string; label: string; roles: UserRole[] };

const NAV_LINKS: NavLink[] = [
  { href: "/schedule", label: "Schedule", roles: ["member"] },
  { href: "/admin/class-schedule", label: "Class Schedule", roles: ["admin"] },
  { href: "/my-workouts", label: "My Workouts", roles: ["athlete"] },
  { href: "/my-workouts/pantheon", label: "Pantheon", roles: ["athlete", "member"] },
  { href: "/admin/coaching-assignments", label: "Coaching Assignments", roles: ["admin"] },
  { href: "/account/billing", label: "Billing", roles: ["member", "athlete"] },
];

type DashboardCategory = {
  label: string;
  items: { href: string; label: string; description: string }[];
};

const DASHBOARD_CATEGORIES: DashboardCategory[] = [
  {
    label: "Programme",
    items: [
      { href: "/admin/workouts", label: "Workouts", description: "Master workout definitions" },
      { href: "/admin/class-schedule", label: "Class Schedule", description: "Slots, bookings & attendance" },
      { href: "/admin/coaching-assignments", label: "Coaching Assignments", description: "Athlete programming board" },
      { href: "/admin/challenges", label: "Challenges", description: "Seasonal training goals" },
    ],
  },
  {
    label: "Revenue",
    items: [
      { href: "/admin/finance", label: "Finance Dashboard", description: "Revenue metrics & trends" },
      { href: "/admin/finance/operations", label: "Finance Operations", description: "Invoices, payments & credits" },
    ],
  },
  {
    label: "Analytics",
    items: [
      { href: "/admin/metrics", label: "Metrics", description: "Events, revenue & engagement" },
      { href: "/admin/reviews", label: "Reviews", description: "Workout feedback queue" },
      { href: "/admin/wellbeing", label: "Wellbeing", description: "Injury flags & follow-up" },
    ],
  },
  {
    label: "Settings",
    items: [
      { href: "/admin/settings", label: "Settings", description: "Appearance, gamification & level taxonomy" },
    ],
  },
];

function pathActive(pathname: string, href: string) {
  if (href === "/admin") {
    return (
      pathname === "/admin" ||
      (pathname.startsWith("/admin") &&
        !pathname.startsWith("/admin/class-schedule") &&
        !pathname.startsWith("/admin/coaching-assignments") &&
        !pathname.startsWith("/admin/finance") &&
        !pathname.startsWith("/admin/metrics") &&
        !pathname.startsWith("/admin/settings") &&
        !pathname.startsWith("/admin/workouts"))
    );
  }
  return pathname.startsWith(href);
}

function DashboardDropdown({ pathname }: { pathname: string }) {
  const [open, setOpen] = useState(false);
  const [activeCategory, setActiveCategory] = useState<string | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  const isAdminActive =
    pathname.startsWith("/admin") &&
    !pathname.startsWith("/admin/class-schedule") &&
    !pathname.startsWith("/admin/coaching-assignments");

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
    <div ref={ref} className="relative">
      <Link
        href="/admin"
        className="rounded-full px-3 py-1 text-sm font-semibold transition-colors"
        style={{
          background: isAdminActive ? "var(--border)" : "transparent",
          color: isAdminActive ? "var(--text)" : "var(--dim)",
        }}
        onMouseEnter={() => setOpen(true)}
      >
        Dashboard
      </Link>

      {open ? (
        <div
          className="absolute left-0 top-full mt-1 flex rounded-2xl shadow-[0_20px_60px_rgba(0,0,0,0.7)]"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", zIndex: 100 }}
          onMouseLeave={() => { setOpen(false); setActiveCategory(null); }}
        >
          {/* Category list */}
          <div className="w-40 border-r py-1.5" style={{ borderColor: "var(--border)" }}>
            {DASHBOARD_CATEGORIES.map((cat) => (
              <button
                key={cat.label}
                className="flex w-full items-center justify-between gap-2 px-4 py-2 text-left text-xs font-semibold transition-colors"
                style={{
                  color: activeCategory === cat.label ? "var(--text)" : "var(--muted)",
                  background: activeCategory === cat.label ? "color-mix(in srgb, var(--text) 5%, transparent)" : "transparent",
                }}
                onMouseEnter={() => setActiveCategory(cat.label)}
                onClick={() => setActiveCategory(cat.label)}
                type="button"
              >
                {cat.label}
                <span style={{ color: "var(--dim)" }}>›</span>
              </button>
            ))}
          </div>

          {/* Sub-items */}
          {activeCategory ? (
            <div className="w-56 py-1.5">
              {DASHBOARD_CATEGORIES.find((c) => c.label === activeCategory)?.items.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="block px-4 py-2.5 transition-colors hover:bg-[color-mix(in_srgb,var(--text)_4%,transparent)]"
                  onClick={() => { setOpen(false); setActiveCategory(null); }}
                >
                  <p className="text-sm font-semibold" style={{ color: pathname.startsWith(item.href) ? "var(--primary)" : "var(--text)" }}>
                    {item.label}
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
  const pathname = usePathname();
  const { tokens, currentUser, signOut } = useSession();
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const [msgOpen, setMsgOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const role = (currentUser?.role ?? "") as UserRole;
  const initials = currentUser?.nickname
    ? currentUser.nickname.slice(0, 2).toUpperCase()
    : "?";
  const avatarUrl = currentUser?.avatar_url ?? null;

  const financeQuery = useQuery({
    queryKey: ["my", "finance"],
    enabled: Boolean(tokens?.access_token) && role !== "admin",
    queryFn: () => fetchMyFinance(tokens!.access_token),
    staleTime: 2 * 60 * 1000,
  });
  const outstandingCents = financeQuery.data?.total_outstanding_balance_cents ?? 0;

  const unreadQuery = useQuery({
    queryKey: ["messages", "unread"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchUnreadCount(tokens!.access_token),
    staleTime: 15 * 1000,
    refetchInterval: 30 * 1000,
  });
  const unreadCount = unreadQuery.data?.unread_count ?? 0;

  // Subscribe to notification channel for live unread count updates
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
      <div className="mx-auto flex w-full max-w-7xl items-center gap-4 px-5">
        <Link
          href="/"
          className="shrink-0 text-xs font-bold uppercase tracking-[0.28em]"
          style={{ color: "var(--text)" }}
        >
          Milos
        </Link>

        <nav className="flex flex-1 items-center gap-1">
          {role === "admin" ? <DashboardDropdown pathname={pathname} /> : null}
          {NAV_LINKS.filter((link) => link.roles.includes(role)).map((link) => {
            const active = pathActive(pathname, link.href);
            const showBalanceBadge = link.href === "/account/billing" && outstandingCents > 0;
            return (
              <Link
                key={link.href}
                href={link.href}
                className="relative rounded-full px-3 py-1 text-sm font-semibold transition-colors"
                style={{
                  background: active ? "var(--border)" : "transparent",
                  color: active ? "var(--text)" : "var(--dim)",
                }}
              >
                {link.label}
                {showBalanceBadge && (
                  <span
                    className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] font-bold"
                    style={{ background: "var(--danger)", color: "#fff" }}
                  >
                    !
                  </span>
                )}
              </Link>
            );
          })}

          {/* Messages button — opens dropdown panel, does not navigate */}
          <div className="relative">
            <button
              type="button"
              className="relative rounded-full px-3 py-1 text-sm font-semibold transition-colors"
              style={{
                background: msgOpen ? "var(--border)" : "transparent",
                color: msgOpen ? "var(--text)" : "var(--dim)",
              }}
              onClick={() => setMsgOpen((v) => !v)}
            >
              Messages
              {unreadCount > 0 && (
                <span
                  className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9px] font-bold"
                  style={{ background: "var(--primary)", color: "var(--bg)" }}
                >
                  {unreadCount > 99 ? "99+" : unreadCount}
                </span>
              )}
            </button>
            {msgOpen ? <DirectMessagesPanel onClose={() => setMsgOpen(false)} /> : null}
          </div>

        </nav>

        <NotificationBell />

        <div ref={menuRef} className="relative shrink-0">
          <button
            className="flex items-center gap-2 rounded-full py-1 pl-1 pr-3 text-sm font-semibold transition-colors"
            style={{ background: "var(--panel)", color: "var(--text)" }}
            onClick={() => setMenuOpen((v) => !v)}
            type="button"
          >
            {avatarUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={avatarUrl}
                alt={currentUser?.nickname ?? ""}
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
            <span className="text-[10px]" style={{ color: "var(--dim)" }}>▾</span>
          </button>

          {menuOpen ? (
            <div
              className="absolute right-0 top-full mt-2 w-44 overflow-hidden rounded-2xl py-1 shadow-[0_16px_60px_rgba(0,0,0,0.6)]"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <div className="border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
                <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                  Signed in as
                </p>
                <p className="mt-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {currentUser.nickname}
                </p>
                <p className="mt-0.5 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {currentUser.role}
                </p>
              </div>
              <Link
                href="/profile"
                className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                style={{ color: "var(--text-soft)" }}
                onClick={() => setMenuOpen(false)}
              >
                Profile
              </Link>
              {role !== "admin" && (
                <Link
                  href="/account/billing"
                  className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                  style={{ color: "var(--text-soft)" }}
                  onClick={() => setMenuOpen(false)}
                >
                  Billing
                </Link>
              )}
              <button
                className="w-full px-4 py-2.5 text-left text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                style={{ color: "var(--primary)" }}
                onClick={() => { signOut(); setMenuOpen(false); }}
                type="button"
              >
                Sign out
              </button>
            </div>
          ) : null}
        </div>
      </div>
    </header>
  );
}
