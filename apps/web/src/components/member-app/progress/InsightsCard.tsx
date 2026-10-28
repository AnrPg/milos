"use client";

import { useId } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { dismissInsight, fetchMyInsights, myInsightsKey, restoreInsights, type Insight, type MyInsights } from "@/api/insights";
import { ClientCard, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";
import { insightSlot, insightValues, shownWeeks, type InsightSlot } from "@/lib/progress/insights";

/**
 * Πρόοδος › Insights (ADR-166): one fixed slot after Φορτίο. At most a few
 * findings, in the rules' fixed order, each dismissible (the next one takes
 * its place); nothing before there is enough data, and always «Ένδειξη, όχι
 * ιατρική συμβουλή». The slot keeps its place in every state (§8.5). Not
 * narrowed by the page's range or provider chips: the rules always read the
 * last twelve weeks, as the note says.
 */
export function InsightsCard() {
  const t = useTranslations("Insights");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const client = useQueryClient();
  const key = myInsightsKey();

  const query = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchMyInsights(token!),
    staleTime: 5 * 60_000,
  });

  const onSaved = (data: MyInsights) => client.setQueryData(key, data);
  const dismiss = useMutation({ mutationFn: (rule: Insight["rule"]) => dismissInsight(token!, rule), onSuccess: onSaved });
  const restore = useMutation({ mutationFn: () => restoreInsights(token!), onSuccess: onSaved });
  const busy = dismiss.isPending || restore.isPending;

  return (
    <ClientCard id="insights" title={t("title")}>
      {query.isPending ? (
        <LoadingLine />
      ) : query.isError ? (
        <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
      ) : (
        <InsightsBody
          slot={insightSlot(query.data)}
          busy={busy}
          onDismiss={(rule) => dismiss.mutate(rule)}
          onRestore={() => restore.mutate()}
        />
      )}
      {dismiss.isError || restore.isError ? (
        <div className="mt-3">
          <QueryProblem error={dismiss.error ?? restore.error} />
        </div>
      ) : null}
    </ClientCard>
  );
}

function InsightsBody({
  slot,
  busy,
  onDismiss,
  onRestore,
}: {
  slot: InsightSlot;
  busy: boolean;
  onDismiss: (rule: Insight["rule"]) => void;
  onRestore: () => void;
}) {
  const t = useTranslations("Insights");
  const noteId = useId();

  return (
    <div className="flex flex-col gap-3" data-testid="insights" data-state={slot.state}>
      {slot.state === "insights" ? (
        <ul className="flex flex-col gap-2">
          {slot.insights.map((insight) => (
            <InsightRow key={insight.rule} insight={insight} noteId={noteId} busy={busy} onDismiss={onDismiss} />
          ))}
        </ul>
      ) : (
        <EmptyLine>
          {slot.state === "all_hidden"
            ? t("empty.allHidden")
            : slot.state === "no_pattern"
              ? t("empty.noPattern", { window: slot.windowWeeks })
              : slot.dataWeeks < slot.minWeeks
                ? t("empty.collecting", { weeks: slot.dataWeeks, min: slot.minWeeks })
                : t("empty.moreEntries")}
        </EmptyLine>
      )}
      {slot.hiddenCount > 0 ? (
        <div className="flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--muted)" }}>
          <span>{t("hidden", { count: slot.hiddenCount })}</span>
          <button
            type="button"
            onClick={onRestore}
            disabled={busy}
            className="rounded-full px-2 py-0.5 font-semibold disabled:opacity-60"
            style={{ color: "var(--primary)" }}
          >
            {t("restore")}
          </button>
        </div>
      ) : null}
      <p id={noteId} className="text-xs" style={{ color: "var(--dim)" }}>
        {slot.state === "insights"
          ? t("noteWithWeeks", { weeks: shownWeeks(slot.insights) })
          : t("note")}
      </p>
    </div>
  );
}

const DECIMALS = new Set(["ratio", "hours", "delta"]);

function InsightRow({
  insight,
  noteId,
  busy,
  onDismiss,
}: {
  insight: Insight;
  noteId: string;
  busy: boolean;
  onDismiss: (rule: Insight["rule"]) => void;
}) {
  const t = useTranslations("Insights");
  const format = useFormatter();
  const message = insightValues(insight);
  if (!message) return null;

  const values = Object.fromEntries(
    Object.entries(message.values).map(([name, value]) => [
      name,
      typeof value === "number" && DECIMALS.has(name)
        ? format.number(value, { maximumFractionDigits: 1 })
        : value,
    ]),
  );

  return (
    <li
      className="flex items-start justify-between gap-3 rounded-xl px-3 py-2"
      style={{ background: "var(--panel-muted)" }}
      aria-describedby={noteId}
      data-rule={insight.rule}
    >
      <p className="min-w-0 text-sm" style={{ color: "var(--text)" }}>
        {t(`rules.${message.key}`, values)}
      </p>
      <button
        type="button"
        onClick={() => onDismiss(insight.rule)}
        disabled={busy}
        aria-label={t("dismiss")}
        title={t("dismiss")}
        className="-mr-1 shrink-0 rounded-full px-2 text-base leading-6 disabled:opacity-60"
        style={{ color: "var(--muted)" }}
      >
        <span aria-hidden="true">×</span>
      </button>
    </li>
  );
}
