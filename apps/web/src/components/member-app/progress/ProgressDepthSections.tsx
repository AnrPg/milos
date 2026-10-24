"use client";

import { useQuery } from "@tanstack/react-query";

import type { ProgressQuery } from "@/api/account-training";
import { fetchMyTrainingDepth, myTrainingDepthKey } from "@/api/training-depth";
import { useSession } from "@/components/session-provider";

import { TrainingDepthCards } from "./TrainingDepthCards";

/**
 * Πρόοδος › Μυϊκή κάλυψη, Ποιότητες, Φορτίο (ADR-165) for the member, under
 * the page's own range and provider chips (the exercise filter does not
 * narrow them). One request feeds the three fixed slots.
 */
export function ProgressDepthSections({ filter }: { filter: ProgressQuery }) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const query = useQuery({
    queryKey: myTrainingDepthKey(token, filter.range, filter.sources),
    enabled: Boolean(token),
    queryFn: () => fetchMyTrainingDepth(token!, filter.range, filter.sources),
    placeholderData: (previous) => previous,
    staleTime: 60_000,
  });

  const base = {
    pending: query.isPending,
    error: query.isError ? query.error : null,
    onRetry: () => void query.refetch(),
  };

  return (
    <TrainingDepthCards
      coverage={{ ...base, data: query.data?.coverage }}
      qualities={{ ...base, data: query.data?.qualities }}
      load={{ ...base, data: query.data?.load }}
      hideEmpty
    />
  );
}
