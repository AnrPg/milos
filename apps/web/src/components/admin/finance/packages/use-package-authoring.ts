"use client";

import { useQuery } from "@tanstack/react-query";

import { listAdminLocations } from "@/api/facility";
import { fetchPackageCatalog } from "@/api/finance";
import { listAdminClassTypes } from "@/api/schedule";
import { fetchGymStaff } from "@/api/staff";
import { useSession } from "@/components/session-provider";

/** Catalog document, class types and locations shared by the package wizard and editor. */
export function usePackageAuthoring(token: string) {
  const catalogQuery = useQuery({
    queryKey: ["admin", "finance", "package-catalog"],
    enabled: Boolean(token),
    queryFn: () => fetchPackageCatalog(token),
    staleTime: 5 * 60 * 1000,
  });

  const classTypesQuery = useQuery({
    queryKey: ["admin", "class-types"],
    enabled: Boolean(token),
    queryFn: () => listAdminClassTypes(token),
  });

  const locationsQuery = useQuery({
    queryKey: ["admin", "locations"],
    enabled: Boolean(token),
    queryFn: () => listAdminLocations(token),
  });

  return {
    catalog: catalogQuery.data ?? null,
    classTypes: classTypesQuery.data ?? [],
    locations: locationsQuery.data ?? [],
    isLoading: catalogQuery.isLoading,
    error: catalogQuery.error,
  };
}

export type CoachOption = { id: string; name: string | null };

/**
 * Staff who can be named as a package's personal trainer: the gym's owners,
 * admins and coaches by their role in this gym (ADR-098 gives coaches admin rights).
 */
export function useStaffCoaches(enabled = true): CoachOption[] {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const query = useQuery({
    queryKey: ["staff", "members"],
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchGymStaff(token),
    staleTime: 5 * 60 * 1000,
  });
  return (query.data ?? []).map((member) => ({ id: member.user_id, name: member.nickname ?? null }));
}
