"use client";

import { useCallback, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchSavedFilters, rememberFilters, type FilterSurface, type SavedFilters } from "@/api/saved-filters";
import { useSession } from "@/components/session-provider";

import { emptyListFilter, parseListFilter, type ListFilter, type ListFilterShape } from "./list-filter";

/** The saved filters of a surface; one cache entry however many screens read it. */
export const savedFiltersKey = (surface: FilterSurface, token: string | null) => ["saved-filters", surface, token] as const;

/**
 * A list screen's filter that follows the member across devices (ADR-151):
 * it starts from the last-used filter stored for the surface (or `fallback`
 * when there is none or it cannot be read) and stores every change. `null`
 * until the stored one is known, so the screen asks for its data once.
 *
 * With `within`, the filter is one entry of the surface's params (a club's
 * Ροή by club id, the Feed's posts under `posts`), so screens sharing a
 * surface keep each other's choices.
 */
export function useRememberedFilter<T extends object>(
  surface: FilterSurface,
  parse: (params: Record<string, unknown> | null) => T,
  fallback: T,
  /** False when the surface's own endpoint stores it (Ημερολόγιο: `remember=true`). */
  persist = true,
  within: string | null = null,
) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const key = savedFiltersKey(surface, token);
  const saved = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchSavedFilters(token!, surface),
    staleTime: Infinity,
    retry: false,
  });
  const [chosen, setChosen] = useState<{ within: string | null; value: T } | null>(null);
  const stored = useMemo(() => {
    if (saved.isError) return fallback;
    if (!saved.isSuccess) return null;
    const params = saved.data?.last_used ?? null;
    const entry = within === null ? params : params?.[within];
    return parse(entry && typeof entry === "object" ? (entry as Record<string, unknown>) : null);
  }, [saved.isSuccess, saved.isError, saved.data, parse, fallback, within]);

  const setFilter = useCallback(
    (next: T) => {
      setChosen({ within, value: next });
      if (!persist || !token) return;
      const cacheKey = savedFiltersKey(surface, token);
      const current = queryClient.getQueryData<SavedFilters>(cacheKey)?.last_used ?? {};
      const params = within === null ? { v: 1, ...next } : { ...current, [within]: next };
      void rememberFilters(token, surface, params)
        .then((result) => queryClient.setQueryData(cacheKey, result))
        .catch(() => undefined);
    },
    [token, surface, persist, within, queryClient],
  );

  // A choice made for another entry (another club) does not carry over.
  const own = chosen && chosen.within === within ? chosen.value : null;
  return { filter: own ?? stored, setFilter, changed: own !== null };
}

/** A remembered `ListFilter` of a declared shape (see `list-filter.ts`). */
export function useListFilter<S extends ListFilterShape>(surface: FilterSurface, shape: S, within: string | null = null) {
  const parse = useCallback((params: Record<string, unknown> | null) => parseListFilter(shape, params), [shape]);
  const empty = useMemo(() => emptyListFilter(shape), [shape]);
  const { filter, setFilter } = useRememberedFilter<ListFilter<S>>(surface, parse, empty, true, within);
  return { filter, setFilter, empty };
}
