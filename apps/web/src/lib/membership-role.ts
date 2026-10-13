"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchOrganizationMemberships, type OrganizationMembership } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { surfaceRole, type View } from "@/lib/role-navigation";
import { useView } from "@/lib/view-mode";

export type TenantMembershipRole =
  | "owner"
  | "admin"
  | "coach"
  | "front_desk"
  | "accountant"
  | "janitor"
  | "member"
  | "athlete";
export type SurfaceRole = "admin" | "member" | "athlete";

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

// Any staff role opens the staff pages; "My training" switches a staff member
// who is also a client to the client pages (ADR-103).
export function surfaceRoleForMembership(
  membership: OrganizationMembership | null,
  view: View = "staff",
): SurfaceRole {
  return surfaceRole(membership, view);
}

export function useSelectedMembershipRole() {
  const { status, tokens } = useSession();
  const selectedOrganizationSlug = useOrganizationSlug();
  const view = useView();
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token);

  const membershipsQuery = useQuery({
    queryKey: ["organization-memberships", tokens?.access_token],
    enabled: authenticated,
    queryFn: () => fetchOrganizationMemberships(tokens!.access_token),
    staleTime: 60_000,
  });

  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];
  const membership = selectedMembership(memberships, selectedOrganizationSlug);
  const role = surfaceRoleForMembership(membership, view);

  return {
    role,
    membershipRole: membership?.role as TenantMembershipRole | undefined,
    membership,
    memberships,
    selectedOrganizationSlug,
    isLoading: membershipsQuery.isLoading,
  };
}
