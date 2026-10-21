"use client";

import { useCallback, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchSavedFilters, rememberFilters, type FilterSurface } from "@/api/saved-filters";
import { useSession } from "@/components/session-provider";

/**
 * A list screen's filter that follows the member across devices (ADR-151):
 * it starts from the last-used filter stored for the surface (or `fallback`
 * when there is none or it cannot be read) and stores every change. `null`
 * until the stored one is known, so the screen asks for its data once.
 */
export function useRememberedFilter<T extends object>(
  surface: FilterSurface,
  parse: (params: Record<string, unknown> | null) => T,
  fallback: T,
  /** False when the surface's own endpoint stores it (Ημερολόγιο: `remember=true`). */
  persist = true,
) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const saved = useQuery({
    queryKey: ["my", "filters", surface, token],
    enabled: Boolean(token),
    queryFn: () => fetchSavedFilters(token!, surface),
    staleTime: Infinity,
    retry: false,
  });
  const [chosen, setChosen] = useState<T | null>(null);
  const stored = useMemo(
    () => (saved.isSuccess ? parse(saved.data.last_used) : saved.isError ? fallback : null),
    [saved.isSuccess, saved.isError, saved.data, parse, fallback],
  );

  const setFilter = useCallback(
    (next: T) => {
      setChosen(next);
      if (persist && token) void rememberFilters(token, surface, { v: 1, ...next }).catch(() => undefined);
    },
    [token, surface, persist],
  );

  return { filter: chosen ?? stored, setFilter, changed: chosen !== null };
}
