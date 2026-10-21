"use client";

import { useId } from "react";
import { useTranslations } from "next-intl";

import type { BodySeries, BodyShape, BodyTrend } from "@/api/body";
import { formatDelta, formatMetric, seriesPaths, seriesSummary, shapePath } from "@/lib/body";
import { DeltaBadge, key } from "@/components/body/BodyBits";

const WIDTH = 300;
const HEIGHT = 72;

/**
 * One metric over a range. Numbers draw the readings and a smoothed line;
 * «Μόνο τάση» draws the real smoothed line from the server's 0..1 `shape`
 * (no scale, no values: the server never sends them); «Κρυφό» shows neither.
 */
export function SeriesChart({
  display,
  points,
  trend,
  shape,
  unit,
  label,
  rangeLabel,
  locale,
  hiddenNote,
}: {
  display: BodySeries["display"];
  points: BodySeries["points"];
  trend: BodyTrend | null | undefined;
  shape?: BodyShape | null;
  unit: string;
  label: string;
  rangeLabel: string;
  locale: string;
  hiddenNote?: React.ReactNode;
}) {
  const t = useTranslations("Body");
  const titleId = useId();

  if (display === "hidden") {
    return (
      <div data-testid="body-chart" data-display="hidden" className="flex flex-col gap-1">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("chartHiddenTitle", { metric: label })}</p>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{hiddenNote ?? t("chartHiddenBody")}</p>
      </div>
    );
  }

  if (display === "trend") {
    const path = shapePath(shape, WIDTH, HEIGHT);
    const word = trend ? t(key("trend", trend)) : t("trendNotYet");
    return (
      <div data-testid="body-chart" data-display="trend" className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between gap-2">
          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t("chartTrendEyebrow", { metric: label, range: rangeLabel })}
          </span>
          <b className="text-sm" style={{ color: "var(--text)" }} data-testid="body-trend-word">{word}</b>
        </div>
        {path ? (
          <svg viewBox={`0 0 ${WIDTH} ${HEIGHT}`} width="100%" height={HEIGHT} role="img" aria-labelledby={titleId} preserveAspectRatio="none">
            <title id={titleId}>{t("chartTrendAria", { metric: label, trend: word })}</title>
            <path d={path} data-testid="body-trend-line" fill="none" stroke="var(--primary)" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" opacity="0.55" vectorEffect="non-scaling-stroke" />
          </svg>
        ) : null}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("chartTrendNote")}</p>
      </div>
    );
  }

  const summary = seriesSummary(points);
  if (!summary) {
    return (
      <div data-testid="body-chart" data-display="number" className="flex flex-col gap-1">
        <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("chartEyebrow", { metric: label, range: rangeLabel })}
        </span>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("chartNoData")}</p>
      </div>
    );
  }
  const paths = seriesPaths(points, WIDTH, HEIGHT);
  const latest = formatMetric(summary.latest, unit, locale);
  return (
    <div data-testid="body-chart" data-display="number" className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("chartEyebrow", { metric: label, range: rangeLabel })}
        </span>
        <span className="flex items-center gap-2">
          <b className="text-base tabular-nums" style={{ color: "var(--text)" }}>{latest}</b>
          {summary.change !== null ? <DeltaBadge delta={summary.change} unit={unit} locale={locale} /> : null}
        </span>
      </div>
      <svg viewBox={`0 0 ${WIDTH} ${HEIGHT}`} width="100%" height={HEIGHT} role="img" aria-labelledby={titleId} preserveAspectRatio="none">
        <title id={titleId}>
          {summary.change !== null
            ? t("chartAria", { metric: label, value: latest, change: formatDelta(summary.change, unit, locale) })
            : t("chartAriaOne", { metric: label, value: latest })}
        </title>
        <path d={paths.smoothed} fill="none" stroke="var(--primary)" strokeWidth="5" strokeLinecap="round" opacity="0.4" vectorEffect="non-scaling-stroke" />
        <path d={paths.raw} fill="none" stroke="var(--primary)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
      </svg>
    </div>
  );
}
