"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  approveScalingSuggestion,
  dismissScalingSuggestion,
  fetchScalingQueue,
  SCALING_QUEUE_KEY,
  type ScalingSuggestion,
} from "@/api/scaling";
import { approvableCount, approveBody, emptyDraft, type ScalingReviewDraft } from "@/components/scaling/scaling-review";
import { ScalingChangeLine, useRegionLabel } from "@/components/scaling/ScalingParts";
import { useSession } from "@/components/session-provider";
import {
  inputClass,
  inputStyle,
  Pill,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

function SuggestionCard({ suggestion }: { suggestion: ScalingSuggestion }) {
  const t = useTranslations("Scaling");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const regionLabel = useRegionLabel();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<ScalingReviewDraft>(emptyDraft);
  const items = suggestion.items ?? [];
  const done = async () => queryClient.invalidateQueries({ queryKey: SCALING_QUEUE_KEY });

  const approve = useMutation({
    mutationFn: () => approveScalingSuggestion(tokens!.access_token, suggestion.id, approveBody(items, draft)),
    onSuccess: done,
  });
  const dismiss = useMutation({
    mutationFn: () => dismissScalingSuggestion(tokens!.access_token, suggestion.id),
    onSuccess: done,
  });
  const pending = approve.isPending || dismiss.isPending;
  const error = approve.error ?? dismiss.error;
  const date = new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short" }).format(
    new Date(`${suggestion.scheduled_for}T12:00:00`),
  );

  return (
    <li
      className="rounded-[1.4rem] p-4"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      data-testid="scaling-suggestion"
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {suggestion.athlete_nickname ?? i18n("stfUnknownMember")}
            <span style={{ color: "var(--muted)" }}> · {suggestion.workout_title ?? t("queue.workout")}</span>
          </p>
          <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
            {date}
            {(suggestion.injury_regions ?? []).length > 0
              ? ` · ${(suggestion.injury_regions ?? []).map(regionLabel).join(", ")}`
              : ""}
          </p>
        </div>
        <Pill tone="primary">{t("queue.aiBadge")}</Pill>
      </div>

      {suggestion.summary ? (
        <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{suggestion.summary}</p>
      ) : null}

      <ul className="mt-3 space-y-3">
        {items.map((item) => {
          const excluded = Boolean(draft.excluded[item.id]);
          return (
            <li key={item.id} className="space-y-1.5">
              <label className="flex items-start gap-2">
                <input
                  type="checkbox"
                  className="mt-1 h-4 w-4 shrink-0"
                  style={{ accentColor: "var(--primary)" }}
                  checked={!excluded}
                  aria-label={t("queue.include", { movement: item.exercise_name ?? "" })}
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, excluded: { ...current.excluded, [item.id]: !event.target.checked } }))
                  }
                />
                <span className={excluded ? "opacity-50" : undefined}>
                  <ScalingChangeLine item={item} suggested={draft.suggested[item.id] ?? item.suggested} />
                </span>
              </label>
              {!excluded && item.change !== "skip" ? (
                <input
                  className={inputClass}
                  style={inputStyle}
                  maxLength={120}
                  aria-label={t("queue.editSuggested", { movement: item.exercise_name ?? "" })}
                  value={draft.suggested[item.id] ?? item.suggested ?? ""}
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, suggested: { ...current.suggested, [item.id]: event.target.value } }))
                  }
                />
              ) : null}
            </li>
          );
        })}
      </ul>

      {suggestion.scale_level_slug ? (
        <label className="mt-3 flex items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
          <input
            type="checkbox"
            className="h-4 w-4"
            style={{ accentColor: "var(--primary)" }}
            checked={!draft.dropScale}
            onChange={(event) => setDraft((current) => ({ ...current, dropScale: !event.target.checked }))}
          />
          {t("queue.scaleLevel", { level: suggestion.scale_level_label ?? suggestion.scale_level_slug })}
        </label>
      ) : null}

      <textarea
        className={`${inputClass} mt-3 min-h-16`}
        style={inputStyle}
        maxLength={500}
        placeholder={t("queue.notePlaceholder")}
        aria-label={t("queue.notePlaceholder")}
        value={draft.note}
        onChange={(event) => setDraft((current) => ({ ...current, note: event.target.value }))}
      />

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <button
          type="button"
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={pending || approvableCount(items, suggestion.scale_level_slug, draft) === 0}
          onClick={() => approve.mutate()}
        >
          {t("queue.approve")}
        </button>
        <button
          type="button"
          className={secondaryButtonClass}
          style={secondaryButtonStyle}
          disabled={pending}
          onClick={() => dismiss.mutate()}
        >
          {t("queue.dismiss")}
        </button>
      </div>
      {error ? <StatusText tone="error">{localizeError(error, i18n)}</StatusText> : null}
    </li>
  );
}

/**
 * «Προτάσεις κλιμάκωσης» (ADR-174) in the coach's home, under «Πελάτες μου».
 * Shown only while something waits: the feature is off by default, so an
 * empty card for every coach would be clutter. Nothing here reaches an
 * athlete until the coach approves it.
 */
export function ScalingQueue() {
  const t = useTranslations("Scaling");
  const { tokens } = useSession();
  const query = useQuery({
    queryKey: SCALING_QUEUE_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchScalingQueue(tokens!.access_token),
    staleTime: 60_000,
  });
  const suggestions = query.data ?? [];
  if (suggestions.length === 0) return null;

  return (
    <StaffPanel eyebrow={t("queue.eyebrow")} labelledBy="staff-scaling-queue" title={t("queue.title", { count: suggestions.length })}>
      <p className="mb-3 text-xs" style={{ color: "var(--dim)" }}>{t("queue.hint")}</p>
      <ul className="space-y-3">
        {suggestions.map((suggestion) => (
          <SuggestionCard key={suggestion.id} suggestion={suggestion} />
        ))}
      </ul>
    </StaffPanel>
  );
}
