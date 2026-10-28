"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchSavedFilters, rememberFilters, type SavedFilters } from "@/api/saved-filters";
import { CLASS_AUDIENCES, CLASS_LEVELS, WORKOUT_FOCUSES } from "@/api/schedule";

import {
  DEFAULT_SCHEDULE_FILTERS,
  parseScheduleFilters,
  rememberForGym,
  rememberedForGym,
  type ScheduleFilters,
} from "./schedule-filters";

const VOCAB = { levels: CLASS_LEVELS, audiences: CLASS_AUDIENCES, focus: WORKOUT_FOCUSES };
const REMEMBER_DELAY_MS = 800;

/**
 * Plan §5a decision 9: the last filters (and the chosen location) come back
 * silently, per gym. The saved-filters store is account-wide, so the
 * schedule keeps one entry per gym inside its `box_schedule` params.
 */
export function useSchedulePreferences(token: string | null, organizationId: string | null) {
  const queryClient = useQueryClient();
  const queryKey = ["saved-filters", "box_schedule"];
  const saved = useQuery({
    queryKey,
    queryFn: () => fetchSavedFilters(token!, "box_schedule"),
    enabled: Boolean(token),
    staleTime: Infinity,
  });
  const [filters, setFiltersState] = useState<ScheduleFilters>(DEFAULT_SCHEDULE_FILTERS);
  const [locationId, setLocationIdState] = useState<string | null | undefined>(undefined);
  const [restoredFor, setRestoredFor] = useState<string | null>(null);
  const [lastParams, setLastParams] = useState<unknown>(null);
  const timer = useRef<number | null>(null);

  // Restore once per gym, after the saved filters arrive (or fail to).
  if (organizationId && restoredFor !== organizationId && (saved.isSuccess || saved.isError)) {
    const entry = rememberedForGym(saved.data?.last_used ?? null, organizationId);
    setLastParams(saved.data?.last_used ?? null);
    setRestoredFor(organizationId);
    setFiltersState(parseScheduleFilters(entry?.filters, VOCAB));
    setLocationIdState(entry?.locationId);
  }

  const persist = useCallback(
    (nextFilters: ScheduleFilters, nextLocationId: string | null | undefined) => {
      if (!token || !organizationId) return;
      if (timer.current) window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => {
        const params = rememberForGym(lastParams, organizationId, {
          filters: nextFilters,
          ...(nextLocationId === undefined ? {} : { locationId: nextLocationId }),
        });
        setLastParams(params);
        void rememberFilters(token, "box_schedule", params)
          .then((next) => queryClient.setQueryData(["saved-filters", "box_schedule"], next))
          .catch(() => undefined);
      }, REMEMBER_DELAY_MS);
    },
    [lastParams, organizationId, queryClient, token],
  );

  useEffect(
    () => () => {
      if (timer.current) window.clearTimeout(timer.current);
    },
    [],
  );

  const setFilters = useCallback(
    (next: ScheduleFilters) => {
      setFiltersState(next);
      persist(next, locationId);
    },
    [locationId, persist],
  );


  return {
    ready: restoredFor !== null && restoredFor === organizationId,
    filters,
    setFilters,
    /** undefined: nothing remembered, so the home location applies. */
    locationId,
  };
}

/**
 * The location picker remembers the chosen place for its gym right away (the
 * schedule reads it back on return), keeping that gym's filters as they were.
 */
export function useRememberScheduleLocation(token: string | null) {
  const queryClient = useQueryClient();

  return useCallback(
    async (organizationId: string, locationId: string | null) => {
      if (!token) return;
      const key = ["saved-filters", "box_schedule"];
      const current =
        queryClient.getQueryData<SavedFilters>(key) ??
        (await fetchSavedFilters(token, "box_schedule").catch(() => null));
      const entry = rememberedForGym(current?.last_used ?? null, organizationId);
      const params = rememberForGym(current?.last_used ?? null, organizationId, {
        filters: parseScheduleFilters(entry?.filters, VOCAB),
        locationId,
      });
      const next = await rememberFilters(token, "box_schedule", params);
      queryClient.setQueryData(key, next);
    },
    [queryClient, token],
  );
}
