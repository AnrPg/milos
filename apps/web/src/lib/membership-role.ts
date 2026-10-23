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

/**
 * The signed-in person's gym memberships, one cache entry per person. The key
 * is the user, not the access token: a token renewal must not turn the query
 * back into a first load, or every page gated on it (the schedule, the shell)
 * unmounts and loses what is open on it. The fetch always uses the current token.
 */
export function useOrganizationMemberships() {
  const { status, tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const userId = currentUser?.id ?? null;

  return useQuery({
    queryKey: ["organization-memberships", userId],
    enabled: status === "authenticated" && Boolean(token && userId),
    queryFn: () => fetchOrganizationMemberships(token!),
    staleTime: 60_000,
  });
}

export function useSelectedMembershipRole() {
  const selectedOrganizationSlug = useOrganizationSlug();
  const view = useView();
  const membershipsQuery = useOrganizationMemberships();

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
