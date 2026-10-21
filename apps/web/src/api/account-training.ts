import { apiRequest } from "@/api/client";
import type { PRTimelineEntry, ProgressStats, ScoreHistorySeries } from "@/api/content";
import type { components } from "@/api/generated/schema";
import type { EntrySource } from "@/api/providers";
import type { TrainingHistoryPage } from "@/api/training-history";

/**
 * The account read model (ADR-150, ADR-162): history, Πρόοδος and the Vault
 * over every provider the member trains with, freeform and device entries
 * included, each attempt labelled with where it came from.
 */
type RawProgress = components["schemas"]["AccountProgress"];

type ScorePoint = ScoreHistorySeries["points"][number] & { source?: EntrySource };

export type AccountProgress = Omit<RawProgress, "totals" | "weekly" | "consistency" | "pr_timeline" | "score_history"> &
  Pick<ProgressStats, "totals" | "weekly" | "consistency"> & {
    pr_timeline: (PRTimelineEntry & { source?: EntrySource })[];
    score_history: (Omit<ScoreHistorySeries, "points"> & { points: ScorePoint[] })[];
  };
export type AccountScoreSeries = AccountProgress["score_history"][number];
export type AccountVault = components["schemas"]["AccountVault"];
export type VaultGroup = AccountVault["groups"][number];
export type VaultAttempt = VaultGroup["attempts"][number];
export type AccountHistoryPage = components["schemas"]["AccountHistoryPage"];

export const PROGRESS_RANGES = ["4w", "12w", "6m", "1y", "all"] as const;
export type ProgressRange = (typeof PROGRESS_RANGES)[number];

export const VAULT_DISCIPLINES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery"] as const;
export type VaultDiscipline = (typeof VAULT_DISCIPLINES)[number];

/**
 * A source token as the filters take it: a provider's organization id,
 * `freeform` or `device`.
 */
export type SourceToken = string;

export type ProgressQuery = { range: ProgressRange; sources: SourceToken[]; exercise?: string | null };

export type VaultQuery = {
  disciplines: VaultDiscipline[];
  benchmark?: string | null;
  exercise?: string | null;
  sources: SourceToken[];
  date_from?: string | null;
  date_to?: string | null;
};

export const ACCOUNT_PROGRESS_KEY = ["my", "account-progress"] as const;
export const ACCOUNT_VAULT_KEY = ["my", "account-vault"] as const;
export const ACCOUNT_HISTORY_KEY = ["my", "account-history"] as const;

function search(params: Record<string, string | string[] | null | undefined>) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (Array.isArray(value)) {
      if (value.length) query.set(key, value.join(","));
    } else if (value) {
      query.set(key, value);
    }
  }
  const text = query.toString();
  return text ? `?${text}` : "";
}

export async function fetchAccountProgress(token: string, params: ProgressQuery) {
  const data = await apiRequest<{ progress: AccountProgress }>(
    `/me/progress${search({ range: params.range, sources: params.sources, exercise: params.exercise?.trim() })}`,
    { token, scope: "account" },
  );
  return data.progress ?? null;
}

export function fetchAccountVault(token: string, params: VaultQuery) {
  return apiRequest<AccountVault>(
    `/me/vault${search({
      disciplines: params.disciplines,
      benchmark: params.benchmark,
      exercise: params.exercise?.trim(),
      sources: params.sources,
      date_from: params.date_from,
      date_to: params.date_to,
    })}`,
    { token, scope: "account" },
  );
}

export function fetchAccountHistory(
  token: string,
  params: { kind: "workouts" | "classes"; offset: number; limit?: number; sources?: SourceToken[] },
) {
  return apiRequest<AccountHistoryPage>(
    `/me/history${search({
      kind: params.kind,
      offset: String(params.offset),
      limit: params.limit ? String(params.limit) : null,
      sources: params.sources,
    })}`,
    { token, scope: "account" },
  );
}

/**
 * An account history page in the shape the training-log list reads: the
 * execution's own source stays `source`, where it came from is `provider`.
 */
export function asTrainingHistoryPage(page: AccountHistoryPage): TrainingHistoryPage {
  return {
    kind: page.kind,
    offset: page.offset,
    next_offset: page.next_offset,
    total: page.total,
    entries: page.entries.map((entry) => ({
      id: entry.id,
      occurred_at: entry.occurred_at,
      class: entry.class ?? null,
      source: entry.execution_source ?? null,
      provider: entry.source,
      workout: entry.workout ? { id: entry.workout.id ?? undefined, title: entry.workout.title, type: entry.workout.type } : null,
      performance: entry.performance
        ? {
            ...entry.performance,
            execution_id: entry.performance.execution_id ?? entry.id,
            status: entry.performance.status ?? "completed",
            scores: entry.performance.scores ?? [],
          }
        : null,
    })),
  };
}
