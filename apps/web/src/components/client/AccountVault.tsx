"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  ACCOUNT_VAULT_KEY,
  asTrainingHistoryPage,
  fetchAccountHistory,
  fetchAccountVault,
  VAULT_DISCIPLINES,
  type VaultAttempt,
  type VaultGroup,
  type VaultQuery,
} from "@/api/account-training";
import { ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { clientErrorMessage } from "@/components/client/errors";
import { ExecutionPerformanceModal } from "@/components/client/ExecutionPerformanceModal";
import { formatDay } from "@/components/client/format";
import { useRepeatWorkout } from "@/components/client/use-repeat-workout";
import { formatElapsed } from "@/components/client/vault";
import { FilterChipRow, type FilterChip } from "@/components/filters/FilterChipRow";
import { ChoiceChips, FilterPage, FilterSection } from "@/components/filters/FilterPage";
import { useRememberedFilter } from "@/components/filters/use-remembered-filter";
import { TrainingHistory } from "@/components/history/TrainingHistory";
import { LocalizedScore } from "@/components/localized-score";
import { SourceLabel } from "@/components/providers/SourceLabel";
import { useMyProviders, useSourceDirectory } from "@/components/providers/use-providers";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { semanticLabel } from "@/i18n/presentation";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { DEFAULT_VAULT_FILTER, parseVaultFilter, vaultFilterCount } from "@/lib/account-filters";
import { sourceOptions, sourceToken } from "@/lib/provider-sources";
import { defaultHistoryKind } from "@/lib/training-history";
import { DateInput } from "@/components/ui/DateInput";

/**
 * Ημερολόγιο › Vault across providers (ADR-162, board 17 Q4): the same
 * workout done anywhere (Fran at the box and Fran with the coach) is one
 * trend, every attempt labelled with its source. Filters: discipline,
 * benchmark, exercise, source and dates, remembered on the account.
 */
export function AccountVault() {
  const i18n = useUiTranslations();
  const t = useTranslations("Providers");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const { filter, setFilter } = useRememberedFilter("vault", parseVaultFilter, DEFAULT_VAULT_FILTER);
  const vault = useQuery({
    queryKey: [...ACCOUNT_VAULT_KEY, token, filter],
    enabled: Boolean(token) && filter !== null,
    queryFn: () => fetchAccountVault(token!, filter!),
    placeholderData: (previous) => previous,
  });
  const { repeat, pendingId, error } = useRepeatWorkout();
  const [performance, setPerformance] = useState<{ id: string; title: string | null } | null>(null);
  const groups = vault.data?.groups ?? [];

  return (
    <ClientPage title={i18n("jrnWorkoutsTitle")} intro={t("vault.intro")}>
      {filter ? <VaultFilters filter={filter} onChange={setFilter} groups={groups} /> : null}

      {error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
          {clientErrorMessage(error, i18n)}
        </p>
      ) : null}

      {filter === null || vault.isPending ? (
        <LoadingLine />
      ) : vault.isError ? (
        <QueryProblem error={vault.error} onRetry={() => void vault.refetch()} />
      ) : groups.length === 0 ? (
        <div className="flex flex-col items-start gap-3">
          <EmptyLine>{vaultFilterCount(filter) > 0 ? t("filter.empty") : i18n("clHistoryEmpty")}</EmptyLine>
          {vaultFilterCount(filter) > 0 ? (
            <button
              type="button"
              onClick={() => setFilter(DEFAULT_VAULT_FILTER)}
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text)" }}
            >
              {t("filter.clear")}
            </button>
          ) : null}
        </div>
      ) : (
        <ul className="grid gap-3 lg:grid-cols-2">
          {groups.map((group) => (
            <VaultGroupCard
              key={group.identity}
              group={group}
              onPerformance={(attempt) => setPerformance({ id: attempt.id, title: group.title })}
              onRepeat={(attempt) =>
                attempt.master_workout_id
                  ? void repeat({ id: attempt.id, master_workout_id: attempt.master_workout_id, scale_level_slug: attempt.scale_level_slug })
                  : undefined
              }
              pendingId={pendingId}
            />
          ))}
        </ul>
      )}

      {token && currentUser ? (
        <TrainingHistory
          id="history"
          queryKey={["me", "account", currentUser.id]}
          fetchPage={async (kind, offset) => asTrainingHistoryPage(await fetchAccountHistory(token, { kind, offset, limit: 10 }))}
          defaultKind={defaultHistoryKind(currentUser.role)}
        />
      ) : null}

      {performance ? (
        <ExecutionPerformanceModal executionId={performance.id} workoutTitle={performance.title} onClose={() => setPerformance(null)} />
      ) : null}
    </ClientPage>
  );
}

function VaultFilters({
  filter,
  onChange,
  groups,
}: {
  filter: VaultQuery;
  onChange: (filter: VaultQuery) => void;
  groups: VaultGroup[];
}) {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const directory = useSourceDirectory();
  const [pageOpen, setPageOpen] = useState(false);
  const set = (patch: Partial<VaultQuery>) => onChange({ ...filter, ...patch });
  const sources = sourceOptions(directory, {
    freeform: t("source.freeform"),
    device: t("source.device"),
    former: (name) => t("source.former", { name }),
  });
  const disciplines = VAULT_DISCIPLINES.map((value) => ({ value, label: semanticLabel(value, i18n) || value }));
  const benchmarks = useMemo(() => {
    const seen = new Map<string, string>();
    for (const group of groups) if (group.benchmark) seen.set(group.benchmark, group.title ?? group.benchmark);
    if (filter.benchmark && !seen.has(filter.benchmark)) seen.set(filter.benchmark, filter.benchmark);
    return [...seen].map(([value, label]) => ({ value, label }));
  }, [groups, filter.benchmark]);

  const chips: FilterChip[] = [
    {
      key: "sources",
      kind: "menu",
      label: t("filter.allSources"),
      options: sources,
      selected: filter.sources,
      multiple: true,
      onChange: (values) => set({ sources: values }),
    },
    {
      key: "disciplines",
      kind: "menu",
      label: t("filter.discipline"),
      options: disciplines,
      selected: filter.disciplines,
      multiple: true,
      onChange: (values) => set({ disciplines: values as VaultQuery["disciplines"] }),
    },
    ...(benchmarks.length
      ? [
          {
            key: "benchmark",
            kind: "menu" as const,
            label: t("filter.benchmark"),
            options: benchmarks,
            selected: filter.benchmark ? [filter.benchmark] : [],
            multiple: false,
            onChange: (values: string[]) => set({ benchmark: values[0] ?? null }),
          },
        ]
      : []),
  ];

  return (
    <>
      <FilterChipRow
        ariaLabel={t("filter.title")}
        activeCount={vaultFilterCount(filter)}
        onOpenFilters={() => setPageOpen(true)}
        onClear={() => onChange(DEFAULT_VAULT_FILTER)}
        chips={chips}
      />
      {pageOpen ? (
        <FilterPage title={t("filter.title")} onClose={() => setPageOpen(false)} onClear={() => onChange(DEFAULT_VAULT_FILTER)}>
          <FilterSection label={t("filter.exercise")}>
            <input
              type="search"
              aria-label={t("filter.exercise")}
              placeholder={t("filter.exercisePlaceholder")}
              defaultValue={filter.exercise ?? ""}
              maxLength={100}
              onBlur={(event) => set({ exercise: event.target.value.trim() || null })}
              onKeyDown={(event) => {
                if (event.key === "Enter") set({ exercise: event.currentTarget.value.trim() || null });
              }}
              className="min-h-11 w-full rounded-2xl px-4 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </FilterSection>
          <FilterSection label={t("filter.source")}>
            <ChoiceChips ariaLabel={t("filter.source")} options={sources} selected={filter.sources} multiple onChange={(values) => set({ sources: values })} />
          </FilterSection>
          <FilterSection label={t("filter.discipline")}>
            <ChoiceChips
              ariaLabel={t("filter.discipline")}
              options={disciplines}
              selected={filter.disciplines}
              multiple
              onChange={(values) => set({ disciplines: values })}
            />
          </FilterSection>
          <FilterSection label={t("filter.dates")}>
            <div className="grid grid-cols-2 gap-3">
              {(["date_from", "date_to"] as const).map((key) => (
                <label key={key} className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
                  {key === "date_from" ? t("filter.from") : t("filter.to")}
                  <DateInput
                    value={filter[key] ?? ""}
                    min={key === "date_to" ? filter.date_from ?? undefined : undefined}
                    max={key === "date_from" ? filter.date_to ?? undefined : undefined}
                    onValueChange={(value) => set({ [key]: value || null })}
                    className="min-h-11 rounded-2xl px-3 text-sm outline-none"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  />
                </label>
              ))}
            </div>
          </FilterSection>
        </FilterPage>
      ) : null}
    </>
  );
}

function VaultGroupCard({
  group,
  onPerformance,
  onRepeat,
  pendingId,
}: {
  group: VaultGroup;
  onPerformance: (attempt: VaultAttempt) => void;
  onRepeat: (attempt: VaultAttempt) => void;
  pendingId: string | null;
}) {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const directory = useSourceDirectory();
  const providers = useMyProviders();
  const selected = providers.data?.selected_organization_id ?? null;
  const [open, setOpen] = useState(false);
  const title = group.title ?? i18n("workout39463a5");
  const latest = group.attempts[0];
  const shown = open ? group.attempts : group.attempts.slice(0, 3);

  return (
    <li className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <h2 className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>{title}</h2>
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
            {group.workout_type ? (
              <>
                <SemanticLabel value={group.workout_type} />
                {" · "}
              </>
            ) : null}
            {i18n("jrnTimesDone", { count: group.attempt_count })}
          </p>
        </div>
        {latest ? <AttemptScore attempt={latest} /> : null}
      </header>
      {group.sources.length > 1 || group.sources.some((source) => source.kind !== "organization" || source.former) || directory.multiple ? (
        <div className="flex flex-wrap gap-1.5" aria-label={t("vault.sources")}>
          {group.sources.map((source) => (
            <SourceLabel key={sourceToken(source)} source={source} directory={directory} always />
          ))}
        </div>
      ) : null}
      <ol className="flex flex-col">
        {shown.map((attempt) => {
          // «Ξανά» starts the workout at the provider Box shows; an attempt
          // from another provider is repeated after switching to it.
          const canRepeat =
            attempt.kind === "execution" &&
            Boolean(attempt.master_workout_id) &&
            (!attempt.organization_id || attempt.organization_id === selected);
          return (
            <li key={`${attempt.kind}:${attempt.id}`} className="flex flex-wrap items-center justify-between gap-2 border-t py-2 text-sm" style={{ borderColor: "var(--border)" }}>
              <span className="flex flex-wrap items-center gap-2" style={{ color: "var(--text-soft)" }}>
                <time dateTime={attempt.at}>{formatDay(attempt.on ?? attempt.at.slice(0, 10), locale, { weekday: undefined })}</time>
                <AttemptScore attempt={attempt} subtle />
                <SourceLabel source={attempt.source} directory={directory} />
              </span>
              {attempt.kind === "execution" ? (
                <span className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => onPerformance(attempt)}
                    className="rounded-full px-3 py-1.5 text-xs font-semibold"
                    style={{ background: "var(--border)", color: "var(--text)" }}
                    aria-label={`${i18n("clSeePerformance")}: ${title}`}
                  >
                    {i18n("clSeePerformance")}
                  </button>
                  {canRepeat ? (
                    <button
                      type="button"
                      onClick={() => onRepeat(attempt)}
                      disabled={Boolean(pendingId)}
                      className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                      aria-label={`${i18n("clDoItAgain")}: ${title}`}
                    >
                      {pendingId === attempt.id ? i18n("clStarting") : i18n("clDoItAgain")}
                    </button>
                  ) : null}
                </span>
              ) : null}
            </li>
          );
        })}
      </ol>
      {group.attempts.length > 3 ? (
        <button type="button" onClick={() => setOpen((value) => !value)} aria-expanded={open} className="self-start text-xs font-semibold" style={{ color: "var(--primary)" }}>
          {open ? i18n("clHideDates") : i18n("clShowDates", { count: group.attempts.length })}
        </button>
      ) : null}
    </li>
  );
}

/** The attempt's first score, else its time. */
function AttemptScore({ attempt, subtle }: { attempt: VaultAttempt; subtle?: boolean }) {
  const score = attempt.scores?.find((item) => item.value !== null && item.value !== undefined);
  const elapsed = attempt.duration_seconds ? formatElapsed(attempt.duration_seconds * 1000) : null;
  if (!score && !elapsed) return null;
  return (
    <span className={subtle ? "tabular-nums" : "text-sm font-semibold tabular-nums"} style={{ color: subtle ? "var(--dim)" : "var(--text)" }}>
      {score ? <LocalizedScore value={score.value} unit={score.unit} /> : <bdi>{elapsed}</bdi>}
    </span>
  );
}
