"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";

const CANVAS_PATHS = ["/admin/workouts/new", "/login"];

type UserRole = "member" | "athlete" | "admin";

type NavLink = { href: string; label: string; roles: UserRole[] };

const NAV_LINKS: NavLink[] = [
  { href: "/schedule", label: "Schedule", roles: ["member"] },
  { href: "/admin/class-schedule", label: "Class Schedule", roles: ["admin"] },
  { href: "/my-workouts", label: "My Workouts", roles: ["athlete"] },
  { href: "/admin/coaching-assignments", label: "Coaching Assignments", roles: ["admin"] },
  { href: "/reviews", label: "Reviews", roles: ["member", "athlete"] },
  { href: "/wellbeing", label: "Wellbeing", roles: ["member", "athlete"] },
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
      { href: "/admin/gamification", label: "Gamification", description: "Streaks, shields & leaderboard" },
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
    label: "System",
    items: [
      { href: "/admin/analytics", label: "Analytics", description: "Events, revenue & engagement" },
      { href: "/admin/reviews", label: "Reviews", description: "Workout feedback queue" },
      { href: "/admin/wellbeing", label: "Wellbeing", description: "Injury flags & follow-up" },
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
        !pathname.startsWith("/admin/analytics") &&
        !pathname.startsWith("/admin/gamification") &&
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
          background: isAdminActive ? "#1a1a28" : "transparent",
          color: isAdminActive ? "#F0EDF8" : "#55556a",
        }}
        onMouseEnter={() => setOpen(true)}
      >
        Dashboard
      </Link>

      {open ? (
        <div
          className="absolute left-0 top-full mt-1 flex rounded-2xl shadow-[0_20px_60px_rgba(0,0,0,0.7)]"
          style={{ background: "#111118", border: "1px solid #1a1a28", zIndex: 100 }}
          onMouseLeave={() => { setOpen(false); setActiveCategory(null); }}
        >
          {/* Category list */}
          <div className="w-40 border-r py-1.5" style={{ borderColor: "#1a1a28" }}>
            {DASHBOARD_CATEGORIES.map((cat) => (
              <button
                key={cat.label}
                className="flex w-full items-center justify-between gap-2 px-4 py-2 text-left text-xs font-semibold transition-colors"
                style={{
                  color: activeCategory === cat.label ? "#F0EDF8" : "#8888aa",
                  background: activeCategory === cat.label ? "rgba(240,237,248,0.05)" : "transparent",
                }}
                onMouseEnter={() => setActiveCategory(cat.label)}
                onClick={() => setActiveCategory(cat.label)}
                type="button"
              >
                {cat.label}
                <span style={{ color: "#3a3a55" }}>›</span>
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
                  className="block px-4 py-2.5 transition-colors hover:bg-[rgba(240,237,248,0.04)]"
                  onClick={() => { setOpen(false); setActiveCategory(null); }}
                >
                  <p className="text-sm font-semibold" style={{ color: pathname.startsWith(item.href) ? "#d95d39" : "#F0EDF8" }}>
                    {item.label}
                  </p>
                  <p className="mt-0.5 text-xs" style={{ color: "#55556a" }}>{item.description}</p>
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
  const { currentUser, signOut } = useSession();
  const [menuOpen, setMenuOpen] = useState(false);
  const [showMessages, setShowMessages] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const role = (currentUser?.role ?? "") as UserRole;
  const initials = currentUser?.nickname
    ? currentUser.nickname.slice(0, 2).toUpperCase()
    : "?";

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
        background: "#0A0A0F",
        borderBottom: "1px solid #1a1a28",
        height: "3.25rem",
      }}
    >
      <div className="mx-auto flex w-full max-w-7xl items-center gap-4 px-5">
        <Link
          href="/"
          className="shrink-0 text-xs font-bold uppercase tracking-[0.28em]"
          style={{ color: "#F0EDF8" }}
        >
          Milos
        </Link>

        <nav className="flex flex-1 items-center gap-1">
          {NAV_LINKS.filter((link) => link.roles.includes(role)).map((link) => {
            const active = pathActive(pathname, link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                className="rounded-full px-3 py-1 text-sm font-semibold transition-colors"
                style={{
                  background: active ? "#1a1a28" : "transparent",
                  color: active ? "#F0EDF8" : "#55556a",
                }}
              >
                {link.label}
              </Link>
            );
          })}
          {role === "admin" ? <DashboardDropdown pathname={pathname} /> : null}
        </nav>

        <div className="relative">
          <button
            type="button"
            onClick={() => setShowMessages((v) => !v)}
            className="relative p-2 rounded-full"
            style={{ color: "#c8c8e0" }}
            aria-label="Messages"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
            </svg>
          </button>
          {showMessages && (
            <DirectMessagesPanel onClose={() => setShowMessages(false)} />
          )}
        </div>

        <NotificationBell />

        <div ref={menuRef} className="relative shrink-0">
          <button
            className="flex items-center gap-2 rounded-full py-1 pl-1 pr-3 text-sm font-semibold transition-colors"
            style={{ background: "#111118", color: "#F0EDF8" }}
            onClick={() => setMenuOpen((v) => !v)}
            type="button"
          >
            <span
              className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold"
              style={{ background: "#9c799c", color: "#0A0A0F" }}
            >
              {initials}
            </span>
            <span className="hidden max-w-[7rem] truncate sm:block" style={{ color: "#c0c0d8" }}>
              {currentUser.nickname}
            </span>
            <span className="text-[10px]" style={{ color: "#55556a" }}>▾</span>
          </button>

          {menuOpen ? (
            <div
              className="absolute right-0 top-full mt-2 w-44 overflow-hidden rounded-2xl py-1 shadow-[0_16px_60px_rgba(0,0,0,0.6)]"
              style={{ background: "#111118", border: "1px solid #1a1a28" }}
            >
              <div className="border-b px-4 py-3" style={{ borderColor: "#1a1a28" }}>
                <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>
                  Signed in as
                </p>
                <p className="mt-1 truncate text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                  {currentUser.nickname}
                </p>
                <p className="mt-0.5 text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                  {currentUser.role}
                </p>
              </div>
              <button
                className="w-full px-4 py-2.5 text-left text-sm font-semibold transition-colors hover:bg-[#1a1a28]"
                style={{ color: "#d95d39" }}
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
