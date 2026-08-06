"use client";

import { usePathname } from "next/navigation";
import { useQuery } from "@tanstack/react-query";

import { fetchOrganizationMemberships } from "@/api/organizations";
import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { useSession } from "@/components/session-provider";

export function adminHref(href: string, organizationSlug: string | null) {
  if (href === "/") return "/";
  if (!organizationSlug) return href;
  return `/org/${organizationSlug}${href}`;
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
  const { status, tokens } = useSession();
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token);

  const membershipsQuery = useQuery({
    queryKey: ["organization-memberships", tokens?.access_token],
    enabled: authenticated,
    queryFn: () => fetchOrganizationMemberships(tokens!.access_token),
    staleTime: 60_000,
  });
  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];

  const pathOrganizationSlug = pathname.match(/^\/org\/([^/]+)/)?.[1] ?? null;
  return pathOrganizationSlug ?? storedOrganizationSlug() ?? memberships[0]?.organization.slug ?? null;
}
