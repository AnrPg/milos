"use client";

import { useQuery } from "@tanstack/react-query";

import {
  BLOCKS_KEY,
  PARTNERS_OVERVIEW_KEY,
  PARTNER_MATCHES_KEY,
  PARTNER_SETTINGS_KEY,
  fetchBlocks,
  fetchPartnerDeck,
  fetchPartnerMatches,
  fetchPartnerSettings,
  fetchPartnerSuggestions,
  fetchPartnersOverview,
  partnerDeckKey,
  partnerSuggestionsKey,
  type PartnerFilters,
} from "@/api/partners";
import { useSession } from "@/components/session-provider";
import { useRealtimeFallbackInterval } from "@/lib/realtime";

import { PARTNERS_FALLBACK_REFETCH_MS } from "./partners-realtime";

export function usePartnersToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/** Partners as it applies to me: verification, my profile, the options. */
export function usePartnersOverview(enabled = true) {
  const token = usePartnersToken();
  return useQuery({
    queryKey: PARTNERS_OVERVIEW_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchPartnersOverview(token!),
    staleTime: 60_000,
  });
}

export function usePartnerDeck(filters: PartnerFilters, enabled: boolean) {
  const token = usePartnersToken();
  return useQuery({
    queryKey: partnerDeckKey(filters),
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchPartnerDeck(token!, filters),
    staleTime: 5 * 60_000,
  });
}

/** My matches; live updates refresh them, the slow refetch is a safety net. */
export function usePartnerMatches(enabled = true) {
  const token = usePartnersToken();
  const fallback = useRealtimeFallbackInterval(PARTNERS_FALLBACK_REFETCH_MS);
  return useQuery({
    queryKey: PARTNER_MATCHES_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchPartnerMatches(token!),
    staleTime: 30_000,
    refetchInterval: fallback,
  });
}

export function usePartnerSuggestions(matchId: string, enabled: boolean) {
  const token = usePartnersToken();
  return useQuery({
    queryKey: partnerSuggestionsKey(matchId),
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchPartnerSuggestions(token!, matchId),
    staleTime: 5 * 60_000,
  });
}

export function usePartnerSettings() {
  const token = usePartnersToken();
  return useQuery({ queryKey: PARTNER_SETTINGS_KEY, enabled: Boolean(token), queryFn: () => fetchPartnerSettings(token!) });
}

export function useBlocks() {
  const token = usePartnersToken();
  return useQuery({ queryKey: BLOCKS_KEY, enabled: Boolean(token), queryFn: () => fetchBlocks(token!) });
}
