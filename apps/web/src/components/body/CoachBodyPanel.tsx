"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchClientBodySeries, fetchClientBodySnapshots, type BodyMetric, type BodyRange } from "@/api/body";
import { SeriesChart } from "@/components/body/BodyChart";
import { BodyPhotoView, Chip, DeltaBadge, Eyebrow, dateFormat, key } from "@/components/body/BodyBits";
import { CompareSlider } from "@/components/body/ComparePage";
import { useBodyToken } from "@/components/body/use-body";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { METRICS, POSES, RANGES, defaultComparePair, formatDelta, formatMetric, metricDeltas, sharedPoses, snapshotChange, summaryMetrics, unitOf } from "@/lib/body";

/**
 * The coach's «Σώμα» tab of a client (ADR-158 §5, board 13 q7): only the
 * snapshots the member shared, a chart per metric, the compare slider with
 * photos only where the member shared them, weight as the member chose to
 * see it. Every open is logged and the member can see it, so the page says so.
 */
export function CoachBodyPanel({ userId, nickname }: { userId: string; nickname: string }) {
  const t = useTranslations("Body");
  const locale = useUiLocale();
  const token = useBodyToken();
  const snapshots = useQuery({
    queryKey: ["staff", "clients", userId, "body"],
    enabled: Boolean(token),
    queryFn: () => fetchClientBodySnapshots(token!, userId, { limit: 100 }),
    staleTime: 5 * 60_000,
  });
  const list = useMemo(() => snapshots.data?.snapshots ?? [], [snapshots.data]);
  const metrics = useMemo(
    () => METRICS.filter((metric) => list.some((snapshot) => typeof snapshot.metrics[metric] === "number" || snapshot.withheld_metrics.includes(metric))),
    [list],
  );
  const [picked, setPicked] = useState<BodyMetric | null>(null);
  const [range, setRange] = useState<BodyRange>("3m");
  const metric = picked && metrics.includes(picked) ? picked : (metrics[0] ?? null);
  // The server applies the member's display choice and logs the read.
  const series = useQuery({
    queryKey: ["staff", "clients", userId, "body", "series", metric, range],
    enabled: Boolean(token && metric),
    queryFn: () => fetchClientBodySeries(token!, userId, metric!, range),
    staleTime: 5 * 60_000,
  });
  const pair = defaultComparePair(list);
  const [from, setFrom] = useState<string | null>(null);
  const [to, setTo] = useState<string | null>(null);
  const fromSnapshot = list.find((item) => item.id === (from ?? pair?.from));
  const toSnapshot = list.find((item) => item.id === (to ?? pair?.to));
  const poses = sharedPoses(fromSnapshot, toSnapshot);
  const [pickedPose, setPose] = useState<string | null>(null);
  const pose = poses.find((item) => item === pickedPose) ?? poses[0] ?? null;
  const dates = dateFormat(locale);
  const units = list[0]?.units ?? "metric";
  const withheld = list.some((snapshot) => snapshot.withheld_metrics.length > 0) || list.some((snapshot) => snapshot.weight_display !== "number");

  const notice = (
    <p className="flex items-center gap-1.5 text-xs" style={{ color: "var(--dim)" }} data-testid="coach-body-notice">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
        <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z" />
        <circle cx="12" cy="12" r="3" />
      </svg>
      {t("coachNotice", { name: nickname })}
    </p>
  );

  if (snapshots.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (snapshots.isError) return <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("coachLoadError")}</p>;
  if (list.length === 0) {
    return (
      <div className="flex flex-col gap-2">
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("coachEmpty", { name: nickname })}</p>
        {notice}
      </div>
    );
  }

  const selectStyle = { background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" };
  return (
    <div className="flex flex-col gap-5" data-testid="coach-body">
      <div className="grid gap-5 md:grid-cols-2">
        <section className="flex flex-col gap-3">
          {metric ? (
            <>
              {series.isPending ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
              ) : series.isError ? (
                <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("coachLoadError")}</p>
              ) : (
                <SeriesChart
                  display={series.data.display}
                  points={series.data.points}
                  trend={series.data.trend}
                  shape={series.data.shape}
                  unit={series.data.unit || unitOf(metric, [], units)}
                  label={t(key("metric", metric))}
                  rangeLabel={t(key("rangeLong", range))}
                  locale={locale}
                  hiddenNote={t("coachWeightChoice", { name: nickname })}
                />
              )}
              <div role="group" aria-label={t("metricsLabel")} className="flex flex-wrap gap-1.5">
                {metrics.map((item) => (
                  <Chip key={item} selected={item === metric} onClick={() => setPicked(item)}>{t(key("metric", item))}</Chip>
                ))}
              </div>
              <div role="group" aria-label={t("rangeLabel")} className="flex flex-wrap gap-1.5">
                {RANGES.map((item) => (
                  <Chip key={item} selected={item === range} onClick={() => setRange(item)}>{t(key("range", item))}</Chip>
                ))}
              </div>
            </>
          ) : (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("coachNoNumbers")}</p>
          )}
          {withheld ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("coachWeightChoice", { name: nickname })}</p> : null}
        </section>
        <section className="flex flex-col gap-2">
          <Eyebrow>{t("coachShared")}</Eyebrow>
          <ul className="flex flex-col gap-3">
            {list.map((snapshot, index) => {
              const change = snapshotChange(snapshot, list[index + 1]);
              const parts = summaryMetrics(snapshot).map(({ metric: item, value }) =>
                t("summaryPart", { metric: t(key("metricShort", item)), value: formatMetric(value, unitOf(item, [], snapshot.units), locale) }),
              );
              parts.push(snapshot.visibility === "coach_full" ? t("coachWithPhotos") : t("coachWithoutPhotos"));
              return (
                <li key={snapshot.id} className="flex items-center gap-3">
                  <div className="h-12 w-10 shrink-0">
                    <BodyPhotoView photo={snapshot.photos[0]} blur={false} label="" size="thumb" className="h-12 w-10" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <b className="block text-sm" style={{ color: "var(--text)" }}>{dates.dayYear(snapshot.taken_at)}</b>
                    <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>{parts.join(" · ")}</span>
                  </div>
                  {change ? <DeltaBadge delta={change.delta} unit={unitOf(change.metric, [], snapshot.units)} locale={locale} /> : null}
                </li>
              );
            })}
          </ul>
        </section>
      </div>

      {pair && fromSnapshot && toSnapshot ? (
        <section className="flex flex-col gap-3">
          <Eyebrow>{t("compareTitle")}</Eyebrow>
          <div className="flex gap-2">
            {(
              [
                [t("compareFrom"), fromSnapshot.id, setFrom, toSnapshot.id],
                [t("compareTo"), toSnapshot.id, setTo, fromSnapshot.id],
              ] as const
            ).map(([label, value, set, exclude]) => (
              <label key={label} className="flex flex-1 flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
                {label}
                <select value={value} onChange={(event) => set(event.target.value)} className="min-h-11 rounded-xl px-3 text-sm" style={selectStyle}>
                  {list
                    .filter((item) => item.id !== exclude)
                    .map((item) => (
                      <option key={item.id} value={item.id}>{dates.dayYear(item.taken_at)}</option>
                    ))}
                </select>
              </label>
            ))}
          </div>
          {pose ? (
            <div className="flex max-w-sm flex-col gap-2">
              <div role="tablist" aria-label={t("posesLabel")} className="flex gap-1.5">
                {POSES.filter((item) => poses.includes(item)).map((item) => (
                  <Chip key={item} selected={item === pose} onClick={() => setPose(item)}>{t(key("pose", item))}</Chip>
                ))}
              </div>
              <CompareSlider
                key={pose}
                from={fromSnapshot.photos.find((photo) => photo.pose === pose)}
                to={toSnapshot.photos.find((photo) => photo.pose === pose)}
                fromLabel={dates.day(fromSnapshot.taken_at)}
                toLabel={dates.day(toSnapshot.taken_at)}
                mode="slider"
                blur={false}
              />
            </div>
          ) : (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("coachNoPhotos")}</p>
          )}
          <dl className="flex max-w-sm flex-col">
            {metricDeltas(fromSnapshot, toSnapshot).map((row) => (
              <div key={row.metric} className="flex justify-between gap-3 border-b py-1.5 text-sm last:border-b-0" style={{ borderColor: "var(--border)" }}>
                <dt>{t(key("metric", row.metric))}</dt>
                <dd className="font-semibold tabular-nums">{formatDelta(row.delta ?? 0, unitOf(row.metric, [], units), locale)}</dd>
              </div>
            ))}
          </dl>
        </section>
      ) : null}
      {notice}
    </div>
  );
}
