"use client";


import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchPublicTheme } from "@/api/theme";
import { applyTheme, DEFAULT_THEME_SLUG, THEME_STORAGE_KEY } from "@/lib/theme";

export const THEME_UPDATED_EVENT = "milos:theme-updated";

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  
  const themeQuery = useQuery({
    queryKey: ["public", "theme"],
    queryFn: fetchPublicTheme,
    staleTime: 60_000,
  });

  useEffect(() => {
    const slug = themeQuery.data?.theme_slug ?? DEFAULT_THEME_SLUG;
    applyTheme(slug);

    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, slug);
    } catch {
      // Theme persistence is cosmetic; private browsing/storage failures should not affect the app.
    }
  }, [themeQuery.data?.theme_slug]);

  useEffect(() => {
    function handleThemeUpdated(event: Event) {
      const detail = (event as CustomEvent<{ theme_slug?: string }>).detail;
      const slug = detail?.theme_slug ?? DEFAULT_THEME_SLUG;
      applyTheme(slug);

      try {
        window.localStorage.setItem(THEME_STORAGE_KEY, slug);
      } catch {
        // Theme persistence is cosmetic; private browsing/storage failures should not affect the app.
      }

      void themeQuery.refetch();
    }

    window.addEventListener(THEME_UPDATED_EVENT, handleThemeUpdated as EventListener);
    return () => window.removeEventListener(THEME_UPDATED_EVENT, handleThemeUpdated as EventListener);
  }, [themeQuery]);

  return children;
}
