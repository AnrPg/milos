"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useLocale, useTranslations } from "next-intl";

import {
  SUGGESTION_FEEDBACK_REASONS,
  partnerSuggestionsKey,
  proposePartnerPlan,
  sendSuggestionFeedback,
  type PartnerSuggestion,
  type SuggestionFeedbackReason,
} from "@/api/partners";
import { ErrorLine } from "@/components/community/Sheet";
import { useUiTranslations } from "@/i18n/ui";
import { withClock } from "@/lib/clock";

import { partnerErrorMessage } from "./errors";
import { suggestionReasons, type ReasonPart } from "./partners-model";
import { usePartnerSuggestions, usePartnersToken } from "./use-partners";

/**
 * «Κλείστε μαζί» (ADR-280 §4, mockup decision 4 A): up to three ideas from
 * the rule engine, classes of a box you both belong to first, otherwise
 * events and trial classes near you both. Each says why in plain words and
 * never who else goes. «Πρότεινε» posts it in the conversation; a quiet
 * «Δεν ταιριάζει» asks why and takes it away. No ideas, no card.
 */
export function PartnerSuggestions({ matchId, name, onProposed }: { matchId: string; name: string; onProposed: () => void }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const suggestions = usePartnerSuggestions(matchId, true);
  const [dismissed, setDismissed] = useState<string[]>([]);
  const [asking, setAsking] = useState<string | null>(null);

  const propose = useMutation({
    mutationFn: (suggestion: PartnerSuggestion) => proposePartnerPlan(token!, matchId, { kind: suggestion.kind, id: suggestion.id }),
    onSuccess: () => {
      onProposed();
      void queryClient.invalidateQueries({ queryKey: partnerSuggestionsKey(matchId) });
    },
    // «partner_suggestion_unavailable»: the idea went (full, started); show the fresh list.
    onError: () => void queryClient.invalidateQueries({ queryKey: partnerSuggestionsKey(matchId) }),
  });
  const feedback = useMutation({
    mutationFn: ({ key, reason }: { key: string; reason: SuggestionFeedbackReason }) => sendSuggestionFeedback(token!, matchId, key, reason),
    onMutate: ({ key }) => {
      setDismissed((keys) => [...keys, key]);
      setAsking(null);
    },
  });

  const rows = (suggestions.data ?? []).filter((suggestion) => !dismissed.includes(suggestion.key)).slice(0, 3);
  if (rows.length === 0) return null;
  const sharedBox = rows.some((suggestion) => suggestion.kind === "class");

  return (
    <section
      aria-labelledby={`partner-ideas-${matchId}`}
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "color-mix(in srgb, var(--primary) 8%, var(--panel))", border: "1px solid color-mix(in srgb, var(--primary) 45%, transparent)" }}
      data-testid="partner-suggestions"
    >
      <div className="flex flex-col gap-0.5">
        <h2 id={`partner-ideas-${matchId}`} className="text-base font-extrabold" style={{ color: "var(--text)" }}>{t("ideasTitle")}</h2>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{sharedBox ? t("ideasSharedBox") : t("ideasNearBoth")}</p>
      </div>
      <ul className="flex flex-col gap-2">
        {rows.map((suggestion) => (
          <li key={suggestion.key} className="flex flex-col gap-2 rounded-2xl px-3 py-2.5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="partner-suggestion">
            <SuggestionRow
              suggestion={suggestion}
              name={name}
              busy={propose.isPending && propose.variables?.key === suggestion.key}
              onPropose={() => propose.mutate(suggestion)}
            />
            {asking === suggestion.key ? (
              <div role="group" aria-label={t("notForUsWhy")} className="flex flex-wrap items-center gap-1.5">
                <span className="text-xs" style={{ color: "var(--dim)" }}>{t("notForUsWhy")}</span>
                {SUGGESTION_FEEDBACK_REASONS.map((reason) => (
                  <button
                    key={reason}
                    type="button"
                    onClick={() => feedback.mutate({ key: suggestion.key, reason })}
                    className="min-h-9 rounded-full px-3 text-xs font-semibold"
                    style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    {t(`feedback_${reason}`)}
                  </button>
                ))}
              </div>
            ) : (
              <button
                type="button"
                onClick={() => setAsking(suggestion.key)}
                className="min-h-9 self-start text-xs font-semibold"
                style={{ color: "var(--dim)" }}
              >
                {t("notForUs")}
              </button>
            )}
          </li>
        ))}
      </ul>
      <ErrorLine message={partnerErrorMessage(propose.error, t, tUi)} />
    </section>
  );
}

function SuggestionRow({ suggestion, name, busy, onPropose }: { suggestion: PartnerSuggestion; name: string; busy: boolean; onPropose: () => void }) {
  const t = useTranslations("Partners");
  const format = useFormatter();
  const locale = useLocale();
  const when = format.dateTime(
    new Date(suggestion.starts_at),
    withClock(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: suggestion.time_zone ?? undefined }),
  );
  const km = (value: number) => format.number(value, { maximumFractionDigits: 1 });
  const reason = (part: ReasonPart) => {
    switch (part.key) {
      case "reason_shared_time":
        return t(part.key, { time: t(`time_${part.time}`) });
      case "reason_distances":
        return t(part.key, { mine: km(part.mine), theirs: km(part.theirs) });
      case "reason_partner_booked":
        return t(part.key, { name });
      default:
        return t(part.key);
    }
  };
  const reasons = suggestionReasons(suggestion).map(reason);
  return (
    <div className="flex items-start gap-3">
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t(`planKind_${suggestion.kind}`)}</span>
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{suggestion.title ?? t(`planKind_${suggestion.kind}`)}</span>
        <span className="text-sm" style={{ color: "var(--text-soft)" }}>
          {suggestion.place ? t("whenAt", { when, place: suggestion.place }) : when}
        </span>
        {reasons.length > 0 ? (
          <span className="text-xs" style={{ color: "var(--text-soft)" }} data-testid="partner-suggestion-reasons">{reasons.join(" · ")}</span>
        ) : null}
      </div>
      <button
        type="button"
        onClick={onPropose}
        disabled={busy}
        className="min-h-10 shrink-0 rounded-2xl px-3 text-sm font-bold disabled:opacity-50"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--primary)", color: "var(--text)" }}
      >
        {busy ? t("sending") : t("propose")}
      </button>
    </div>
  );
}
