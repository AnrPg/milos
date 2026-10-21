"use client";

import { useEffect, useState } from "react";

import { useSession } from "@/components/session-provider";
import { applyTheme, DEFAULT_THEME_SLUG, normalizeThemeSlug, THEME_STORAGE_KEY } from "@/lib/theme";

export const PERSONAL_THEME_EVENT = "palee:personal-theme";
const PERSONAL_THEME_STORAGE_KEY = "palee:personal-theme-slug";

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

/** Announces the member's own theme (Ρυθμίσεις › Θέμα); null is the default. */
export function announcePersonalTheme(slug: string | null) {
  remember(PERSONAL_THEME_STORAGE_KEY, slug);
  window.dispatchEvent(new CustomEvent(PERSONAL_THEME_EVENT, { detail: { theme_slug: slug } }));
}

/**
 * The page theme: one Palee palette for everyone, light by default or the
 * member's own dark choice. The effective slug is stored for the pre-paint
 * bootstrap script, so a reload does not flash the other variant.
 */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [personal, setPersonal] = useState<string | null>(null);

  useEffect(() => {
    queueMicrotask(() => setPersonal(readPersonalTheme()));
    function handlePersonal(event: Event) {
      setPersonal((event as CustomEvent<{ theme_slug?: string | null }>).detail?.theme_slug ?? null);
    }
    window.addEventListener(PERSONAL_THEME_EVENT, handlePersonal as EventListener);
    return () => window.removeEventListener(PERSONAL_THEME_EVENT, handlePersonal as EventListener);
  }, []);

  const slug = personal ? normalizeThemeSlug(personal) : DEFAULT_THEME_SLUG;

  useEffect(() => {
    applyTheme(slug);
    remember(THEME_STORAGE_KEY, slug);
  }, [slug]);

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
