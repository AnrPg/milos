"use client";

import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchPublicTheme } from "@/api/theme";
import { applyTheme, DEFAULT_THEME_SLUG } from "@/lib/theme";

export const THEME_UPDATED_EVENT = "milos:theme-updated";

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const themeQuery = useQuery({
    queryKey: ["public", "theme"],
    queryFn: fetchPublicTheme,
    staleTime: 60_000,
  });

  useEffect(() => {
    applyTheme(themeQuery.data?.theme_slug ?? DEFAULT_THEME_SLUG);
  }, [themeQuery.data?.theme_slug]);

  useEffect(() => {
    function handleThemeUpdated(event: Event) {
      const detail = (event as CustomEvent<{ theme_slug?: string }>).detail;
      applyTheme(detail?.theme_slug ?? DEFAULT_THEME_SLUG);
      void themeQuery.refetch();
    }

    window.addEventListener(THEME_UPDATED_EVENT, handleThemeUpdated as EventListener);
    return () => window.removeEventListener(THEME_UPDATED_EVENT, handleThemeUpdated as EventListener);
  }, [themeQuery]);

  return children;
}
