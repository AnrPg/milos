"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  WELLNESS_SHARING_KEY,
  fetchWellnessAccessLog,
  fetchWellnessSummarySharing,
  updateWellnessSummarySharing,
  type WellnessSummarySharing as Sharing,
  type WellnessSummarySharingRequest,
} from "@/api/buddies";
import { dateFormat } from "@/components/body/BodyBits";
import { ErrorLine } from "@/components/community/Sheet";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { SwitchRow } from "./BuddyBits";
import { buddyErrorMessage } from "./errors";
import { useBuddyToken } from "./use-buddies";

/**
 * Κοινοποίηση & ορατότητα › the coach's weekly wellness summary (ADR-160
 * §9, board 14): «Ευεξία · εβδομαδιαία σύνοψη» shares counts only;
 * «Λιγούρες στη σύνοψη» adds how many cravings and when, never notes. Then
 * every time a coach opened it.
 */
export function WellnessSummarySharing() {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const dates = dateFormat(locale);
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const sharing = useQuery({
    queryKey: WELLNESS_SHARING_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchWellnessSummarySharing(token!),
  });
  const log = useQuery({
    queryKey: [...WELLNESS_SHARING_KEY, "access-log"],
    enabled: Boolean(token),
    queryFn: () => fetchWellnessAccessLog(token!),
  });
  const update = useMutation({
    mutationFn: (change: WellnessSummarySharingRequest) => updateWellnessSummarySharing(token!, change),
    onMutate: (change) => {
      const previous = queryClient.getQueryData<Sharing>(WELLNESS_SHARING_KEY);
      if (previous) {
        const next = { ...previous, ...change };
        if (change.wellness === false) next.cravings = false;
        queryClient.setQueryData(WELLNESS_SHARING_KEY, next);
      }
      return { previous };
    },
    onError: (_error, _change, context) => {
      if (context?.previous) queryClient.setQueryData(WELLNESS_SHARING_KEY, context.previous);
    },
    onSuccess: (next) => queryClient.setQueryData(WELLNESS_SHARING_KEY, next),
  });

  const wellness = sharing.data?.wellness === true;
  const cravings = wellness && sharing.data?.cravings === true;
  const entries = log.data ?? [];

  return (
    <div className="flex flex-col gap-3" data-testid="wellness-summary-sharing">
      <SwitchRow
        checked={wellness}
        disabled={sharing.isPending || update.isPending}
        onChange={(next) => update.mutate({ wellness: next })}
        label={t("shareWellness")}
        hint={t("shareWellnessHint")}
      />
      <SwitchRow
        checked={cravings}
        disabled={!wellness || sharing.isPending || update.isPending}
        onChange={(next) => update.mutate({ cravings: next })}
        label={t("shareCravings")}
        hint={wellness ? t("shareCravingsHint") : t("shareCravingsNeedsSummary")}
      />
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("shareNever")}</p>
      <ErrorLine message={buddyErrorMessage(update.error ?? sharing.error, t, tUi)} />

      <div className="flex flex-col gap-2 border-t pt-3" style={{ borderColor: "var(--border)" }}>
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("accessLogTitle")}</p>
        {log.isPending ? null : entries.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("accessLogEmpty")}</p>
        ) : (
          <ul className="flex flex-col gap-1" data-testid="wellness-access-log">
            {entries.map((entry) => (
              <li key={entry.id} className="text-sm" style={{ color: "var(--text)" }}>
                {t("accessLogEntry", {
                  coach: entry.reader?.nickname ?? t("aCoach"),
                  date: dates.dateTime(entry.read_at),
                  week: dates.day(entry.week_start),
                })}
                {!entry.shared ? <span style={{ color: "var(--dim)" }}> · {t("accessLogNotShared")}</span> : null}
                {entry.cravings_shown ? <span style={{ color: "var(--dim)" }}> · {t("accessLogCravings")}</span> : null}
                {entry.organization?.name ? <span style={{ color: "var(--dim)" }}> · {entry.organization.name}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
