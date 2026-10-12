"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchPackageCatalog } from "@/api/finance";
import { listAdminClassTypes } from "@/api/schedule";

/** Catalog document and class types shared by the package wizard and editor. */
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

  return {
    catalog: catalogQuery.data ?? null,
    classTypes: classTypesQuery.data ?? [],
    isLoading: catalogQuery.isLoading,
    error: catalogQuery.error,
  };
}
