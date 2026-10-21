"use client";

import { createContext, useCallback, useContext, useMemo, useState, useSyncExternalStore, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import { keepPreviousData, useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  AROUND_AREA_KEY,
  AROUND_KEY,
  fetchAroundArea,
  fetchAroundPins,
  neighbourhoodsKey,
  saveAroundArea,
  searchAround,
  searchAroundKind,
  searchNeighbourhoods,
  type AroundKind,
  type AroundViewport,
} from "@/api/around";
import { ApiError } from "@/api/client";
import {
  deleteSavedFilter,
  fetchSavedFilters,
  rememberFilters,
  saveNamedFilter,
  setSavedFilterAlert,
  type SavedFilter,
  type SavedFilters,
} from "@/api/saved-filters";
import { useSession } from "@/components/session-provider";
import { useDebounced } from "@/hooks/useDebounced";

import {
  DEFAULT_FILTER,
  SCOPE_STORAGE_KEY,
  buildOrigin,
  filterKey,
  isOneOff,
  originKey,
  parseFilter,
  parseScope,
  readStored,
  scopeFromParams,
  writeStored,
  type AroundFilter,
  type HomeScope,
  type OriginChoice,
} from "./around";

const SAVED_KEY = (token: string | null) => ["saved-filters", "around_me", token] as const;
const FEED_PREFS_KEY = (token: string | null) => ["saved-filters", "feed", token] as const;

/** 422 `origin_required`: no area, no box, no place: ask «Πού να ψάξουμε;». */
export function needsOrigin(error: unknown) {
  return error instanceof ApiError && error.payload?.code === "origin_required";
}

/** Our own refusals are not worth retrying; network trouble is, a little. */
function retry(count: number, error: unknown) {
  if (error instanceof ApiError && error.status >= 400 && error.status < 500) return false;
  return count < 2;
}

type AroundState = {
  ready: boolean;
  filter: AroundFilter;
  /** The filter after the slider and taps settle: what queries use. */
  queryFilter: AroundFilter;
  setFilter: (filter: AroundFilter) => void;
  origin: OriginChoice;
  setOrigin: (origin: OriginChoice) => void;
  /** The pin or row picked on the map or in the list. */
  selectedId: string | null;
  setSelectedId: (id: string | null) => void;
  saved: SavedFilter[];
};

const AroundContext = createContext<AroundState | null>(null);

/**
 * The Γύρω μου state shared by /around and its «Δες όλα» pages: the filter
 * (restored from `?filter=<saved id>`, else the last-used one) and where the
 * search starts. It lives in the route's layout, so it survives moving
 * between the sections and a kind's list.
 */
export function AroundProvider({ children }: { children: ReactNode }) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const params = useSearchParams();
  const requestedId = params.get("filter");
  const savedQuery = useSavedAroundFilters();
  const [state, setState] = useState<{ filter: AroundFilter; restored: boolean; appliedId: string | null }>({
    filter: DEFAULT_FILTER,
    restored: false,
    appliedId: null,
  });
  const [origin, setOrigin] = useState<OriginChoice>({ type: "auto" });
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const settled = savedQuery.isSuccess || savedQuery.isError || !token;
  // Restore once the saved filters arrive (or fail to); a notification's
  // `?filter=` applies its saved filter, also when it arrives later.
  if (settled && (!state.restored || (requestedId && requestedId !== state.appliedId))) {
    const fromLink = requestedId ? savedQuery.data?.saved.find((entry) => entry.id === requestedId) : undefined;
    const filter = fromLink
      ? parseFilter(fromLink.params)
      : state.restored
        ? state.filter
        : parseFilter(savedQuery.data?.last_used ?? null);
    setState({ filter, restored: true, appliedId: requestedId });
  }

  const debounced = useDebounced(state.filter, 300);
  const setFilter = useCallback((filter: AroundFilter) => setState((current) => ({ ...current, filter })), []);

  const value = useMemo<AroundState>(
    () => ({
      ready: state.restored,
      filter: state.filter,
      queryFilter: debounced,
      setFilter,
      origin,
      setOrigin,
      selectedId,
      setSelectedId,
      saved: savedQuery.data?.saved ?? [],
    }),
    [debounced, origin, savedQuery.data?.saved, selectedId, setFilter, state.filter, state.restored],
  );

  return <AroundContext.Provider value={value}>{children}</AroundContext.Provider>;
}

export function useAround() {
  const context = useContext(AroundContext);
  if (!context) throw new Error("useAround");
  return context;
}

/** The sections: each kind's top cards, totals and wider counts. */
export function useAroundSearch(limit = 5) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { ready, queryFilter, origin } = useAround();
  return useQuery({
    queryKey: ["around", "search", filterKey(queryFilter), originKey(origin), limit],
    enabled: Boolean(token) && ready,
    placeholderData: keepPreviousData,
    retry,
    queryFn: ({ signal }) =>
      searchAround(
        token!,
        // A one-off search elsewhere doesn't change the remembered filter.
        { filter: queryFilter, origin: buildOrigin(origin), limit, remember: !isOneOff(origin) },
        signal,
      ),
  });
}

/** One kind, cursor-paged («Δες όλα»). Without a provider it searches with the defaults. */
export function useAroundKind(kind: AroundKind, options: { filter?: AroundFilter; origin?: OriginChoice; limit?: number; enabled?: boolean } = {}) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const filter = options.filter ?? DEFAULT_FILTER;
  const origin = options.origin ?? { type: "auto" };
  const limit = options.limit ?? 20;
  return useInfiniteQuery({
    queryKey: ["around", "kind", kind, filterKey(filter), originKey(origin), limit],
    enabled: Boolean(token) && (options.enabled ?? true),
    initialPageParam: null as string | null,
    retry,
    queryFn: ({ pageParam, signal }) =>
      searchAroundKind(token!, kind, { filter, origin: buildOrigin(origin), cursor: pageParam, limit }, signal),
    getNextPageParam: (page) => page.next_cursor ?? undefined,
  });
}

/** Map pins inside a viewport («Ψάξε εδώ»); null bbox waits. */
export function useAroundPins(bbox: AroundViewport | null, filter: AroundFilter) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: ["around", "pins", filterKey(filter), bbox ? [bbox.west, bbox.south, bbox.east, bbox.north].map((value) => value.toFixed(4)).join(",") : null],
    enabled: Boolean(token) && Boolean(bbox),
    placeholderData: keepPreviousData,
    retry,
    queryFn: ({ signal }) => fetchAroundPins(token!, bbox!, filter, signal),
  });
}

export function useAroundArea() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({ queryKey: AROUND_AREA_KEY, enabled: Boolean(token), retry, queryFn: () => fetchAroundArea(token!) });
}

export function useSaveAroundArea() {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (ids: string[]) => saveAroundArea(tokens!.access_token, ids),
    onSuccess: (area) => {
      queryClient.setQueryData(AROUND_AREA_KEY, area);
      void queryClient.invalidateQueries({ queryKey: AROUND_KEY });
      void queryClient.invalidateQueries({ queryKey: ["social", "summary"] });
    },
  });
}

/** Gazetteer search for the area picker; the caller debounces `q`, stale requests are aborted. */
export function useNeighbourhoodSearch(q: string) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const query = q.trim();
  return useQuery({
    queryKey: neighbourhoodsKey(query),
    enabled: Boolean(token) && query.length >= 2,
    placeholderData: keepPreviousData,
    staleTime: 5 * 60_000,
    retry,
    queryFn: ({ signal }) => searchNeighbourhoods(token!, query, signal),
  });
}

export function useSavedAroundFilters() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: SAVED_KEY(token),
    enabled: Boolean(token),
    staleTime: 60_000,
    retry,
    queryFn: () => fetchSavedFilters(token!, "around_me"),
  });
}

/** «Αποθήκευση ως…», rename, delete and «Ειδοποίησέ με» for saved Γύρω μου filters. */
export function useSavedFilterActions() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const put = (next: SavedFilters) => queryClient.setQueryData(SAVED_KEY(token), next);

  const save = useMutation({
    mutationFn: ({ name, filter }: { name: string; filter: AroundFilter }) => saveNamedFilter(token!, "around_me", name, filter),
    onSuccess: put,
  });
  const remove = useMutation({
    mutationFn: (id: string) => deleteSavedFilter(token!, "around_me", id),
    onSuccess: put,
  });
  const alert = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) => setSavedFilterAlert(token!, "around_me", id, enabled),
    onMutate: async ({ id, enabled }) => {
      const previous = queryClient.getQueryData<SavedFilters>(SAVED_KEY(token));
      if (previous) put({ ...previous, saved: previous.saved.map((entry) => (entry.id === id ? { ...entry, alert: enabled } : entry)) });
      return { previous };
    },
    onError: (_error, _vars, context) => {
      if (context?.previous) put(context.previous);
    },
    onSuccess: put,
  });
  // No rename route: save under the new name (keeping the alert), then drop the old one.
  const rename = useMutation({
    mutationFn: async ({ entry, name }: { entry: SavedFilter; name: string }) => {
      let next = await saveNamedFilter(token!, "around_me", name, entry.params);
      const created = next.saved.find((item) => item.name === name);
      if (created && created.id !== entry.id) {
        if (entry.alert && !created.alert) next = await setSavedFilterAlert(token!, "around_me", created.id, true);
        next = await deleteSavedFilter(token!, "around_me", entry.id);
      }
      return next;
    },
    onSuccess: put,
  });
  return { save, remove, alert, rename };
}

// ------------------------------------------------------------------ Αρχική scope

const subscribeStorage = (onChange: () => void) => {
  window.addEventListener("storage", onChange);
  window.addEventListener("palee:home-scope", onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener("palee:home-scope", onChange);
  };
};

/**
 * «Τα clubs μου | Γύρω μου», remembered on the account (the `feed` surface's
 * last-used params, ADR-151) and mirrored on the device for the first paint.
 */
export function useHomeScope() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const local = useSyncExternalStore(
    subscribeStorage,
    () => parseScope(readStored(SCOPE_STORAGE_KEY)),
    () => null,
  );
  const prefs = useQuery({
    queryKey: FEED_PREFS_KEY(token),
    enabled: Boolean(token),
    staleTime: Infinity,
    retry,
    queryFn: () => fetchSavedFilters(token!, "feed"),
  });
  const remote = scopeFromParams(prefs.data?.last_used ?? null);

  const setScope = useCallback(
    (scope: HomeScope) => {
      writeStored(SCOPE_STORAGE_KEY, scope);
      window.dispatchEvent(new Event("palee:home-scope"));
      if (!token) return;
      const current = queryClient.getQueryData<SavedFilters>(FEED_PREFS_KEY(token));
      const params = { ...(current?.last_used ?? {}), scope };
      void rememberFilters(token, "feed", params)
        .then((next) => queryClient.setQueryData(FEED_PREFS_KEY(token), next))
        .catch(() => undefined);
    },
    [queryClient, token],
  );

  return {
    /** The device's choice wins; a new device takes the account's. */
    scope: local ?? remote ?? null,
    settled: local !== null || prefs.isSuccess || prefs.isError || !token,
    setScope,
  };
}

export { DEFAULT_FILTER };
