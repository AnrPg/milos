"use client";

import { usePathname } from "next/navigation";
import { useQuery } from "@tanstack/react-query";

import { fetchOrganizationMemberships, type OrganizationMembership } from "@/api/organizations";
import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { useSession } from "@/components/session-provider";
import { FRESHNESS } from "@/lib/query-policy";
import { hasStaffRole } from "@/lib/role-navigation";

export const ORGANIZATION_MEMBERSHIPS_KEY = ["organization-memberships"] as const;

/**
 * The signed-in person's gym memberships: one cache entry per person, shared
 * by every screen and the shell. The key is the user, not the access token: a
 * token renewal must not turn the query back into a first load, or every page
 * gated on it (the schedule, the shell) unmounts and loses what is open on it.
 * The fetch always uses the current token. Changes arrive through the actions
 * that invalidate the key and the realtime `organization_branding` sync.
 */
export function useOrganizationMemberships() {
  const { status, tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const userId = currentUser?.id ?? null;

  return useQuery({
    queryKey: [...ORGANIZATION_MEMBERSHIPS_KEY, userId],
    enabled: status === "authenticated" && Boolean(token && userId),
    queryFn: () => fetchOrganizationMemberships(token!),
    staleTime: FRESHNESS.account,
  });
}

export function adminHref(href: string, organizationSlug: string | null) {
  if (href === "/") return "/";
  if (!organizationSlug) return href;
  return `/org/${organizationSlug}${href}`;
}

export function rememberSelectedOrganization(slug: string) {
  try {
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, slug);
  } catch {}
}

// Admin-ish roles land in the tenant's admin dashboard, everyone else lands
// on their ordinary homepage - both under the /org/:slug prefix, which is
// what tells Home to render the tenant workspace instead of the platform
// console for a vendor account.
export function membershipWorkspaceHref(membership: OrganizationMembership) {
  const slug = membership.organization.slug;
  return hasStaffRole(membership) ? `/org/${slug}/admin` : `/org/${slug}`;
}

function storedOrganizationSlug() {
  if (typeof window === "undefined") return null;

  try {
    return window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY);
  } catch {
    return null;
  }
}

/**
 * Resolves the organization slug for the current admin session: URL path first
 * (so links stay consistent while browsing), then the last-selected slug in
 * localStorage, then the user's first membership as a final fallback.
 */
export function useOrganizationSlug(): string | null {
  const pathname = usePathname();
  const membershipsQuery = useOrganizationMemberships();
  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];

  const pathOrganizationSlug = pathname.match(/^\/org\/([^/]+)/)?.[1] ?? null;
  return pathOrganizationSlug ?? storedOrganizationSlug() ?? memberships[0]?.organization.slug ?? null;
}

/**
 * ADR-179: the IANA zone of a gym the signed-in account belongs to (the
 * current one by default): the clock its classes and events are planned
 * on, and whether an admin confirmed it. `zone` is null while unknown, so
 * callers fall back to the device's clock.
 */
export function useOrganizationTimeZoneStatus(slug?: string | null): { zone: string | null; confirmed: boolean } {
  const currentSlug = useOrganizationSlug();
  const membershipsQuery = useOrganizationMemberships();
  const target = slug ?? currentSlug;
  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];
  const organization = memberships.find((membership) => membership.organization.slug === target)?.organization as
    | { timezone?: string | null; timezone_confirmed?: boolean }
    | undefined;
  return { zone: organization?.timezone ?? null, confirmed: organization?.timezone_confirmed === true };
}

/** ADR-179: the zone of a gym the account belongs to (the current one by default), or null. */
export function useOrganizationTimeZone(slug?: string | null): string | null {
  return useOrganizationTimeZoneStatus(slug).zone;
}
