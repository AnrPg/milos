"use client";

import { useQuery } from "@tanstack/react-query";

import {
  BLOCKS_KEY,
  PARTNER_MATCHES_KEY,
  PARTNER_SETTINGS_KEY,
  fetchBlocks,
  fetchPartnerDeck,
  fetchPartnerMatches,
  fetchPartnerSettings,
  fetchPartnersClub,
  partnerDeckKey,
  partnersClubKey,
  type PartnerFilters,
} from "@/api/partners";
import { useSession } from "@/components/session-provider";

import { PARTNERS_FALLBACK_REFETCH_MS } from "./partners-realtime";

export function usePartnersToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/** Partners in one club as it applies to me: offered?, my profile, the options. */
export function usePartnersClub(clubId: string) {
  const token = usePartnersToken();
  return useQuery({
    queryKey: partnersClubKey(clubId),
    enabled: Boolean(token),
    queryFn: () => fetchPartnersClub(token!, clubId),
    staleTime: 60_000,
  });
}

export function usePartnerDeck(clubId: string, filters: PartnerFilters, enabled: boolean) {
  const token = usePartnersToken();
  return useQuery({
    queryKey: partnerDeckKey(clubId, filters),
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchPartnerDeck(token!, clubId, filters),
    staleTime: 5 * 60_000,
  });
}

/** My matches across clubs; live updates refresh them, the slow refetch is a safety net. */
export function usePartnerMatches(enabled = true) {
  const token = usePartnersToken();
  return useQuery({
    queryKey: PARTNER_MATCHES_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchPartnerMatches(token!),
    staleTime: 30_000,
    refetchInterval: PARTNERS_FALLBACK_REFETCH_MS,
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
