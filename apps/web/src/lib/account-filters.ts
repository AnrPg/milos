import {
  PROGRESS_RANGES,
  VAULT_DISCIPLINES,
  type ProgressQuery,
  type ProgressRange,
  type VaultDiscipline,
  type VaultQuery,
} from "@/api/account-training";

/**
 * The Vault and Πρόοδος filters across providers (ADR-162, board 17 Q4),
 * read back from a remembered filter defensively: unknown values drop out,
 * and «Όλοι» (no source) is the default.
 */
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function strings(value: unknown): string[] {
  if (Array.isArray(value)) return value.filter((item): item is string => typeof item === "string");
  if (typeof value === "string") return value.split(",").filter(Boolean);
  return [];
}

function text(value: unknown, max = 100) {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
}

function day(value: unknown) {
  return typeof value === "string" && DATE.test(value) ? value : null;
}

export const DEFAULT_VAULT_FILTER: VaultQuery = {
  disciplines: [],
  benchmark: null,
  exercise: null,
  sources: [],
  date_from: null,
  date_to: null,
};

export const DEFAULT_PROGRESS_FILTER: ProgressQuery = { range: "12w", sources: [], exercise: null };

export function parseVaultFilter(params: Record<string, unknown> | null): VaultQuery {
  if (!params) return DEFAULT_VAULT_FILTER;
  return {
    disciplines: strings(params.disciplines).filter((value): value is VaultDiscipline =>
      (VAULT_DISCIPLINES as readonly string[]).includes(value),
    ),
    benchmark: text(params.benchmark, 60),
    exercise: text(params.exercise),
    sources: strings(params.sources),
    date_from: day(params.date_from),
    date_to: day(params.date_to),
  };
}

export function vaultFilterCount(filter: VaultQuery) {
  return [
    filter.disciplines.length > 0,
    Boolean(filter.benchmark),
    Boolean(filter.exercise?.trim()),
    filter.sources.length > 0,
    Boolean(filter.date_from || filter.date_to),
  ].filter(Boolean).length;
}

export function parseProgressFilter(params: Record<string, unknown> | null): ProgressQuery {
  if (!params) return DEFAULT_PROGRESS_FILTER;
  const range = (PROGRESS_RANGES as readonly string[]).includes(params.range as string)
    ? (params.range as ProgressRange)
    : DEFAULT_PROGRESS_FILTER.range;
  return { range, sources: strings(params.sources), exercise: text(params.exercise) };
}
