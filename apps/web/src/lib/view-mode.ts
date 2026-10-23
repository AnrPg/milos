"use client";

import { useEffect, useSyncExternalStore } from "react";
import { usePathname } from "next/navigation";

import type { View } from "@/lib/role-navigation";

// The console or the social app (ADR-103, amended 2026-10-23): staff land on
// the console by default; its «Social» button switches the whole app to the
// social app (Feed, floating bar), and Εγώ › Διαχείριση switches back. Every
// staff member can switch, with or without a client role. Remembered per
// device. People without a staff role always get the social app.
// Opening a console URL (/admin…, /org/:slug/admin…, the kiosk, door and
// poster screens) opens the console and remembers it.
const KEY = "palee.view";
export const DEFAULT_VIEW: View = "staff";
const listeners = new Set<() => void>();

/** The stored choice; "client" only once the person chose the social app. */
export function parseStoredView(value: string | null | undefined): View {
  return value === "client" ? "client" : DEFAULT_VIEW;
}

function read(): View {
  try {
    return parseStoredView(window.localStorage.getItem(KEY));
  } catch {
    return DEFAULT_VIEW;
  }
}

export function setView(view: View) {
  try {
    window.localStorage.setItem(KEY, view);
  } catch {}
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Console pages: /admin…, also under /org/:slug. */
export function isConsolePath(pathname: string | null | undefined) {
  const path = (pathname ?? "/").replace(/^\/org\/[^/]+(?=\/|$)/, "") || "/";
  return path === "/admin" || path.startsWith("/admin/");
}

/** The view a page renders with: a console URL always opens the console. */
export function viewFor(pathname: string | null | undefined, stored: View): View {
  return isConsolePath(pathname) ? "staff" : stored;
}

// The console URL last remembered as "staff": once per visit, so the
// console's «Social» switch is not undone before it leaves the page.
let rememberedConsolePath: string | null = null;

export function useView(): View {
  const pathname = usePathname();
  const stored = useSyncExternalStore(subscribe, read, () => DEFAULT_VIEW);
  const consolePath = isConsolePath(pathname);
  // Remember the console once it was opened by its URL.
  useEffect(() => {
    if (!consolePath) {
      rememberedConsolePath = null;
      return;
    }
    if (rememberedConsolePath === pathname) return;
    rememberedConsolePath = pathname;
    if (read() !== "staff") setView("staff");
  }, [consolePath, pathname]);
  return viewFor(pathname, stored);
}
