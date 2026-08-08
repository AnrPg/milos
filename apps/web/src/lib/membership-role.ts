"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchOrganizationMemberships, type OrganizationMembership } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { useOrganizationSlug } from "@/lib/organization-slug";

export type TenantMembershipRole = "owner" | "admin" | "coach" | "member" | "athlete";
export type SurfaceRole = "admin" | "member" | "athlete";

const ADMIN_MEMBERSHIP_ROLES = new Set<TenantMembershipRole>(["owner", "admin", "coach"]);

export function selectedMembership(
  memberships: OrganizationMembership[],
  selectedOrganizationSlug: string | null,
) {
  if (!selectedOrganizationSlug) return memberships[0] ?? null;
  return (
    memberships.find((membership) => membership.organization.slug === selectedOrganizationSlug) ??
    null
  );
}

export function surfaceRoleForMembership(membership: OrganizationMembership | null): SurfaceRole {
  const membershipRole = membership?.role as TenantMembershipRole | undefined;

  if (membershipRole && ADMIN_MEMBERSHIP_ROLES.has(membershipRole)) return "admin";
  if (membershipRole === "athlete") return "athlete";
  if (membershipRole === "member") return "member";
  return "member";
}

export function useSelectedMembershipRole() {
  const { status, tokens } = useSession();
  const selectedOrganizationSlug = useOrganizationSlug();
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token);

  const membershipsQuery = useQuery({
    queryKey: ["organization-memberships", tokens?.access_token],
    enabled: authenticated,
    queryFn: () => fetchOrganizationMemberships(tokens!.access_token),
    staleTime: 60_000,
  });

  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];
  const membership = selectedMembership(memberships, selectedOrganizationSlug);
  const role = surfaceRoleForMembership(membership);

  return {
    role,
    membershipRole: membership?.role as TenantMembershipRole | undefined,
    membership,
    memberships,
    selectedOrganizationSlug,
    isLoading: membershipsQuery.isLoading,
  };
}
