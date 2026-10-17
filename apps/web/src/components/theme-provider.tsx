"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchPublicTheme } from "@/api/theme";
import { useSession } from "@/components/session-provider";
import { applyTheme, DEFAULT_THEME_SLUG, normalizeThemeSlug, THEME_STORAGE_KEY } from "@/lib/theme";

export const THEME_UPDATED_EVENT = "milos:theme-updated";
export const PERSONAL_THEME_EVENT = "milos:personal-theme";
const PERSONAL_THEME_STORAGE_KEY = "milos:personal-theme-slug";

function readPersonalTheme(): string | null {
  try {
    return window.localStorage.getItem(PERSONAL_THEME_STORAGE_KEY);
  } catch {
    return null;
  }
}

function remember(key: string, slug: string | null) {
  try {
    if (slug) window.localStorage.setItem(key, slug);
    else window.localStorage.removeItem(key);
  } catch {
    // Theme persistence is cosmetic; private browsing/storage failures should not affect the app.
  }
}

/** Announces the member's own theme (Ρυθμίσεις › Θέμα); null follows the gym's. */
export function announcePersonalTheme(slug: string | null) {
  remember(PERSONAL_THEME_STORAGE_KEY, slug);
  window.dispatchEvent(new CustomEvent(PERSONAL_THEME_EVENT, { detail: { theme_slug: slug } }));
}

/**
 * The page theme: the member's own choice when they made one, else their
 * gym's (public theme). The effective slug is stored for the pre-paint
 * bootstrap script, so a reload does not flash the other theme.
 */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const themeQuery = useQuery({
    queryKey: ["public", "theme"],
    queryFn: fetchPublicTheme,
    staleTime: 60_000,
  });
  const [personal, setPersonal] = useState<string | null>(null);

  useEffect(() => {
    queueMicrotask(() => setPersonal(readPersonalTheme()));
    function handlePersonal(event: Event) {
      setPersonal((event as CustomEvent<{ theme_slug?: string | null }>).detail?.theme_slug ?? null);
    }
    window.addEventListener(PERSONAL_THEME_EVENT, handlePersonal as EventListener);
    return () => window.removeEventListener(PERSONAL_THEME_EVENT, handlePersonal as EventListener);
  }, []);

  const slug = personal ? normalizeThemeSlug(personal) : (themeQuery.data?.theme_slug ?? DEFAULT_THEME_SLUG);

  useEffect(() => {
    applyTheme(slug);
    remember(THEME_STORAGE_KEY, slug);
  }, [slug]);

  useEffect(() => {
    function handleThemeUpdated() {
      void themeQuery.refetch();
    }

    window.addEventListener(THEME_UPDATED_EVENT, handleThemeUpdated);
    return () => window.removeEventListener(THEME_UPDATED_EVENT, handleThemeUpdated);
  }, [themeQuery]);

  return children;
}

/** Keeps the personal theme in step with the signed-in account (cleared on sign-out). */
export function PersonalThemeBridge() {
  const { currentUser, status } = useSession();
  const slug = status === "authenticated" ? (currentUser?.preferred_theme_slug ?? null) : null;
  const known = status !== "loading";

  useEffect(() => {
    if (known) announcePersonalTheme(slug);
  }, [known, slug]);

  return null;
}
