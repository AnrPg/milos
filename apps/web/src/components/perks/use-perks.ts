"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  addPerkCodes,
  claimPerk,
  createStaffPerk,
  fetchMemberPerks,
  fetchPerkCheck,
  fetchStaffPerks,
  perkKeys,
  redeemPerkCheck,
  refreshPerkLink,
  stepStaffPerk,
  updateStaffPerk,
  type MemberPerk,
  type PerkClaim,
  type StaffPerkInput,
} from "@/api/perks";
import { useSession } from "@/components/session-provider";

function useToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? "";
}

/** The member's perks at every provider (one call); screens narrow them to a provider. */
export function useMemberPerks(enabled = true) {
  const token = useToken();
  return useQuery({
    queryKey: perkKeys.member,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchMemberPerks(token),
    staleTime: 60_000,
  });
}

function withClaim(perks: MemberPerk[] | undefined, claim: PerkClaim) {
  return perks?.map((perk) => (perk.id === claim.perk_id ? { ...perk, claim } : perk));
}

export function useClaimPerk() {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (perkId: string) => claimPerk(token, perkId),
    onSuccess: ({ claim }) => {
      queryClient.setQueryData<MemberPerk[]>(perkKeys.member, (perks) => withClaim(perks, claim));
      void queryClient.invalidateQueries({ queryKey: ["me", "billing"] });
    },
  });
}

/** A new QR link for a claim reopened later (the API only signs one right after claiming). */
export function useRefreshPerkLink() {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (claimId: string) => refreshPerkLink(token, claimId),
    onSuccess: (claim) => queryClient.setQueryData<MemberPerk[]>(perkKeys.member, (perks) => withClaim(perks, claim)),
  });
}

// Staff -----------------------------------------------------------------------

export function useStaffPerks() {
  const token = useToken();
  return useQuery({ queryKey: perkKeys.staff, enabled: Boolean(token), queryFn: () => fetchStaffPerks(token) });
}

export function useSavePerk() {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, body }: { id: string | null; body: StaffPerkInput }) => (id ? updateStaffPerk(token, id, body) : createStaffPerk(token, body)),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: perkKeys.staff }),
  });
}

export function useStepPerk() {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, step }: { id: string; step: "publish" | "pause" | "expire" }) => stepStaffPerk(token, id, step),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: perkKeys.staff }),
  });
}

export function useAddPerkCodes() {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, codes }: { id: string; codes: string[] }) => addPerkCodes(token, id, codes),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: perkKeys.staff }),
  });
}

// The store's check page --------------------------------------------------------

export function usePerkCheck(linkToken: string) {
  return useQuery({ queryKey: perkKeys.check(linkToken), queryFn: () => fetchPerkCheck(linkToken), retry: false });
}

export function useRedeemPerkCheck(linkToken: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => redeemPerkCheck(linkToken),
    onSuccess: (check) => queryClient.setQueryData(perkKeys.check(linkToken), check),
  });
}
