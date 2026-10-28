"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

import { FRESHNESS } from "@/lib/query-policy";

export function createAppQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // Fresh data is served from the cache when a screen mounts or the tab
        // comes back; only stale queries of the screens on show refetch.
        staleTime: FRESHNESS.live,
        gcTime: 5 * 60_000,
        retry: 1,
        refetchOnWindowFocus: true,
      },
    },
  });
}

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(createAppQueryClient);

  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}
