"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { dailyStatsKey, fetchRestingHeartRate, type DailyStatsRange } from "@/api/devices";
import { formatDay } from "@/components/client/format";
import { useSession } from "@/components/session-provider";
import { restingHrView } from "@/components/devices/resting-hr";
import { useUiLocale } from "@/i18n/use-ui-locale";

const RANGES: DailyStatsRange[] = ["1m", "3m", "1y"];
const WIDTH = 240;
const HEIGHT = 48;

/**
 * Πρόοδος › Ρυθμός ηρεμίας (ADR-161, board 16 Q4 A): the member's own
 * resting heart rate from a connected device, as an indicator. Shown only
 * when there is data; neutral words, no targets, never advice.
 */
export function RestingHeartRateCard() {
  const t = useTranslations("Devices");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [range, setRange] = useState<DailyStatsRange>("3m");
  const stats = useQuery({
    queryKey: dailyStatsKey(range),
    enabled: Boolean(token),
    queryFn: () => fetchRestingHeartRate(token!, range),
    retry: false,
    placeholderData: (previous) => previous,
  });
  const view = restingHrView(stats.data, WIDTH, HEIGHT);
  if (!view) return null;
  const providers = view.sources
    .map((source) => t(["provider", ["garmin", "apple_health", "health_connect"].includes(source) ? source : "garmin"].join("_")))
    .join(", ");

  return (
    <section className="flex flex-col gap-3 rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="resting-hr-card">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{t("restingTitle")}</p>
        <div role="group" aria-label={t("restingRange")} className="flex gap-1">
          {RANGES.map((option) => (
            <button
              key={option}
              type="button"
              aria-pressed={range === option}
              onClick={() => setRange(option)}
              className="rounded-full px-2.5 py-1 text-xs font-semibold"
              style={{
                background: range === option ? "var(--primary)" : "var(--panel-raised)",
                color: range === option ? "var(--primary-contrast)" : "var(--text)",
                border: "1px solid var(--border)",
              }}
            >
              {t(["restingRange", option].join("_"))}
            </button>
          ))}
        </div>
      </div>
      <div className="flex items-end justify-between gap-4">
        <div>
          <p className="text-3xl font-semibold tracking-tight tabular-nums" style={{ color: "var(--text)" }}>
            {t("bpmValue", { value: view.latest.value })}
          </p>
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            {t("restingLatest", { date: formatDay(view.latest.on, locale, { weekday: undefined, year: undefined }) })}
          </p>
        </div>
        {view.line ? (
          <svg viewBox={`-2 -2 ${WIDTH + 4} ${HEIGHT + 4}`} className="h-12 w-40 shrink-0" aria-hidden="true">
            <polyline points={view.line} fill="none" stroke="var(--primary)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        ) : null}
      </div>
      <p className="text-sm tabular-nums" style={{ color: "var(--text-soft)" }}>
        {t("restingAverage", { value: view.average, days: view.days })} · {t("restingSpread", { low: view.low, high: view.high })}
      </p>
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {t("fromProvider", { provider: providers })} · {t("restingNote")}
      </p>
    </section>
  );
}
