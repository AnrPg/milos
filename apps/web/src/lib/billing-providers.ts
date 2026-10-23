"use client";

import type { OrganizationMembership } from "@/api/organizations";
import { useOrganizationMemberships } from "@/lib/membership-role";

/**
 * Who sees Εγώ › Πληρωμές: people who are a client (member or athlete) of
 * at least one gym or independent coach. Staff-only memberships run their
 * gym from the console, an organiser organisation (ADR-185) provides nobody's
 * training, and a business in demo mode (ADR-184) is not a real provider to
 * its members. The API applies the same rule to `GET /api/me/billing`.
 */
const CLIENT_ROLES = new Set(["member", "athlete"]);

type MembershipLike = Pick<OrganizationMembership, "role" | "roles" | "organization">;

export function isBillingProviderMembership(membership: MembershipLike) {
  const roles = membership.roles && membership.roles.length > 0 ? membership.roles : [membership.role];
  if (!roles.some((role) => CLIENT_ROLES.has(role))) return false;
  if (membership.organization.provider_kind === "organiser") return false;
  return membership.organization.activation !== "demo";
}

export function billingProviderMemberships<T extends MembershipLike>(memberships: T[]): T[] {
  return memberships.filter(isBillingProviderMembership);
}

/**
 * Whether to offer «Πληρωμές» anywhere (the Εγώ list, a menu, the route).
 * `isLoading` stays true until the memberships are known, so callers neither
 * flash the entry nor redirect early.
 */
export function useHasBillingProviders() {
  const query = useOrganizationMemberships();
  const memberships = Array.isArray(query.data) ? query.data : [];
  const providers = billingProviderMemberships(memberships);
  return {
    hasBillingProviders: providers.length > 0,
    providers,
    isLoading: query.isPending,
  };
}
