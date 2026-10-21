"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { clientTrainingDepthKey, COACH_DEPTH_RANGES, fetchClientTrainingDepth, type CoachDepthRange } from "@/api/training-depth";
import { useSession } from "@/components/session-provider";

import { TrainingDepthCards } from "./TrainingDepthCards";

/**
 * The coach's view of a client's muscle coverage, qualities and load
 * (ADR-165), in the profile's «Προπόνηση» tab. Built by the API only from
 * entries the client shares with this gym's coaches; the panel says so. A
 * coach without the client never gets here (the API refuses, nothing shows).
 */
export function CoachTrainingDepthPanel({ userId }: { userId: string }) {
  const t = useTranslations("Depth");
  const providers = useTranslations("Providers");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [range, setRange] = useState<CoachDepthRange>("4w");
  const query = useQuery({
    queryKey: clientTrainingDepthKey(userId, range),
    enabled: Boolean(token),
    queryFn: () => fetchClientTrainingDepth(token!, userId, range),
    placeholderData: (previous) => previous,
    staleTime: 60_000,
    retry: false,
  });

  const base = { pending: query.isPending, error: query.isError ? query.error : null, onRetry: () => void query.refetch() };

  return (
    <div className="flex flex-col gap-3" data-testid="coach-training-depth">
      <div role="group" aria-label={t("coach.range")} className="flex flex-wrap gap-2">
        {COACH_DEPTH_RANGES.map((value) => (
          <button
            key={value}
            type="button"
            aria-pressed={range === value}
            onClick={() => setRange(value)}
            className="min-h-9 rounded-full px-3 text-sm font-semibold"
            style={{
              background: range === value ? "var(--border)" : "transparent",
              border: "1px solid var(--border)",
              color: range === value ? "var(--text)" : "var(--dim)",
            }}
          >
            {providers(`range.${value}`)}
          </button>
        ))}
      </div>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("coach.sharedOnly")}</p>
      <TrainingDepthCards
        audience="coach"
        coverage={{ ...base, data: query.data?.coverage }}
        qualities={{ ...base, data: query.data?.qualities }}
        load={{ ...base, data: query.data?.load }}
      />
    </div>
  );
}
