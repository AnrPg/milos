"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  BODY_CONSENTS_KEY,
  BODY_KEY,
  BODY_SETTINGS_KEY,
  BODY_SNAPSHOTS_KEY,
  fetchBodySettings,
  fetchBodySnapshots,
  fetchHealthConsents,
  updateBodySettings,
  type BodySettingsResponse,
  type BodySettingsUpdate,
} from "@/api/body";
import { useSession } from "@/components/session-provider";

export function useBodyToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/** Settings plus the metric catalog in the person's units. */
export function useBodySettings(enabled = true) {
  const token = useBodyToken();
  return useQuery({
    queryKey: BODY_SETTINGS_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchBodySettings(token!),
    staleTime: 5 * 60_000,
  });
}

/** Partial settings change; the answer replaces the cached settings. */
export function useUpdateBodySettings() {
  const token = useBodyToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (change: BodySettingsUpdate) => updateBodySettings(token!, change),
    onSuccess: (data) => {
      queryClient.setQueryData<BodySettingsResponse>(BODY_SETTINGS_KEY, data);
      // Units and weight display change what every snapshot and series shows.
      void queryClient.invalidateQueries({ queryKey: BODY_KEY, predicate: (query) => query.queryKey[2] !== "settings" });
      void queryClient.invalidateQueries({ queryKey: ["my", "journal"] });
    },
  });
}

/** Snapshots, newest first. */
export function useBodySnapshots(limit = 50) {
  const token = useBodyToken();
  return useInfiniteQuery({
    queryKey: [...BODY_SNAPSHOTS_KEY, limit],
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchBodySnapshots(token!, { cursor: pageParam, limit }),
    getNextPageParam: (last) => last.next_cursor ?? undefined,
  });
}

export function useHealthConsents(enabled = true) {
  const token = useBodyToken();
  return useQuery({
    queryKey: BODY_CONSENTS_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchHealthConsents(token!),
  });
}
