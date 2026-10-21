"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { fetchMyProviders, MY_PROVIDERS_KEY, selectProvider, type Provider } from "@/api/providers";
import { useSession } from "@/components/session-provider";
import { rememberSelectedOrganization } from "@/lib/organization-slug";
import { sourceDirectory } from "@/lib/provider-sources";

/** Everyone who trains the member (ADR-162), shared by Box ▾, filters and labels. */
export function useMyProviders() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: [...MY_PROVIDERS_KEY, token],
    enabled: Boolean(token),
    queryFn: () => fetchMyProviders(token!),
    staleTime: 60_000,
  });
}

export function useSourceDirectory() {
  const providers = useMyProviders();
  return useMemo(() => sourceDirectory(providers.data), [providers.data]);
}

function storedSlug() {
  try {
    return window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY);
  } catch {
    return null;
  }
}

/**
 * Switching provider (board 17 Q1): remembered on the account, so a new
 * device opens Box on the same one, and on this device for the per-gym
 * requests. Everything cached for the previous provider is dropped.
 */
export function useSwitchProvider() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const router = useRouter();
  const pathname = usePathname();
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null);

  const switchTo = useCallback(
    async (provider: Pick<Provider, "organization_id" | "slug">) => {
      if (!token) return false;
      setPending(provider.organization_id);
      setError(null);
      try {
        const providers = await selectProvider(token, provider.organization_id);
        rememberSelectedOrganization(provider.slug);
        queryClient.clear();
        queryClient.setQueryData([...MY_PROVIDERS_KEY, token], providers);
        const scoped = pathname.match(/^\/org\/[^/]+(\/.*)?$/);
        if (scoped) router.push(`/org/${provider.slug}${scoped[1] ?? ""}`);
        else router.refresh();
        return true;
      } catch (cause) {
        setError(cause);
        return false;
      } finally {
        setPending(null);
      }
    },
    [token, queryClient, router, pathname],
  );

  return { switchTo, pending, error };
}

/**
 * A device with no remembered provider opens on the one the account
 * remembers, so the choice follows the member across devices.
 */
export function useAdoptAccountProvider() {
  const providers = useMyProviders();
  const queryClient = useQueryClient();
  useEffect(() => {
    const selected = providers.data?.providers.find((provider) => provider.selected);
    if (!selected || storedSlug()) return;
    rememberSelectedOrganization(selected.slug);
    void queryClient.invalidateQueries({ predicate: (query) => query.queryKey[0] !== MY_PROVIDERS_KEY[0] });
  }, [providers.data, queryClient]);
}
