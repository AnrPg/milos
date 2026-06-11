"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";

const CANVAS_PATHS = ["/admin/workouts/new", "/login"];

type UserRole = "member" | "athlete" | "admin";

const NAV_LINKS: Array<{ href: string; label: string; roles: UserRole[] }> = [
  { href: "/schedule", label: "Schedule", roles: ["member"] },
  { href: "/admin/class-schedule", label: "Class Schedule", roles: ["admin"] },
  { href: "/my-workouts", label: "My Workouts", roles: ["athlete"] },
  { href: "/admin/coaching-assignments", label: "Coaching Assignments", roles: ["admin"] },
  { href: "/reviews", label: "Reviews", roles: ["member", "athlete"] },
  { href: "/wellbeing", label: "Wellbeing", roles: ["member", "athlete"] },
  { href: "/admin/workouts", label: "Admin", roles: ["admin"] },
];

function pathActive(pathname: string, href: string) {
  if (href === "/admin/workouts") {
    return (
      pathname.startsWith("/admin") &&
      !pathname.startsWith("/admin/class-schedule") &&
      !pathname.startsWith("/admin/coaching-assignments")
    );
  }
  return pathname.startsWith(href);
}

export function TopNav() {
  const pathname = usePathname();
  const { currentUser, signOut } = useSession();
  const [menuOpen, setMenuOpen] = useState(false);
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
        </nav>

        {/* Inbox button — inline in nav */}
        <NotificationBell />

        {/* Avatar + kebab menu */}
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
