"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BODY_KEY, fetchBodySeries, type BodyMetric, type BodyRange, type BodySettingsResponse, type BodySnapshot } from "@/api/body";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { SeriesChart } from "@/components/body/BodyChart";
import {
  BodyPhotoView,
  Card,
  Chip,
  DeltaBadge,
  Eyebrow,
  IconButton,
  PillButton,
  PrivacyLine,
  ShareIcon,
  dateFormat,
  key,
} from "@/components/body/BodyBits";
import { ShareBeforeAfterDialog } from "@/components/body/ShareBeforeAfter";
import { useBodySettings, useBodySnapshots, useBodyToken, useUpdateBodySettings } from "@/components/body/use-body";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  METRICS,
  RANGES,
  defaultComparePair,
  formatMetric,
  recordedMetrics,
  sharedPoses,
  snapshotChange,
  summaryMetrics,
  unitOf,
} from "@/lib/body";

/**
 * Ημερολόγιο › Σώμα (vision §7.7, ADR-158, board 13): one chart with metric
 * chips and a range, the compare card, snapshots newest first with the change
 * since the previous one, and «Νέα μέτρηση». Private by default; the whole
 * segment can be switched off in Ρυθμίσεις › Σώμα.
 */
export function BodyPage() {
  const t = useTranslations("Body");
  const settings = useBodySettings();
  const snapshots = useBodySnapshots();
  const update = useUpdateBodySettings();
  const list = useMemo(() => snapshots.data?.pages.flatMap((page) => page.snapshots) ?? [], [snapshots.data]);

  if (settings.data && settings.data.settings.journal_sections.body === false) {
    return (
      <BodyFrame>
        <Card label={t("offTitle")}>
          <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>{t("offTitle")}</h2>
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("offBody")}</p>
          <PillButton primary disabled={update.isPending} onClick={() => update.mutate({ journal_sections: { body: true } })}>
            {t("turnOn")}
          </PillButton>
        </Card>
      </BodyFrame>
    );
  }

  return (
    <BodyFrame>
      {snapshots.isPending || settings.isPending ? (
        <LoadingLine />
      ) : snapshots.isError ? (
        <QueryProblem error={snapshots.error} onRetry={() => void snapshots.refetch()} />
      ) : settings.isError ? (
        <QueryProblem error={settings.error} onRetry={() => void settings.refetch()} />
      ) : list.length === 0 ? (
        <EmptyBody />
      ) : (
        <>
          <ChartCard settings={settings.data} snapshots={list} />
          <CompareCard settings={settings.data} snapshots={list} />
          <SnapshotsCard settings={settings.data} snapshots={list} />
          {snapshots.hasNextPage ? (
            <PillButton disabled={snapshots.isFetchingNextPage} onClick={() => void snapshots.fetchNextPage()}>
              {t("older")}
            </PillButton>
          ) : null}
          <NewMeasureLink />
        </>
      )}
    </BodyFrame>
  );
}

function BodyFrame({ children }: { children: React.ReactNode }) {
  const t = useTranslations("Body");
  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-4xl flex-col gap-4">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h2>
          <Link href="/me/settings/body" className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
            {t("settingsLink")}
          </Link>
        </div>
        {children}
      </div>
    </main>
  );
}

export function NewMeasureLink() {
  const t = useTranslations("Body");
  return (
    <Link
      href="/journal/body/new"
      className="flex min-h-12 items-center justify-center rounded-2xl text-base font-bold"
      style={{ border: "1px solid var(--border)", color: "var(--text)", background: "var(--panel-raised)" }}
    >
      {t("newMeasure")}
    </Link>
  );
}

function EmptyBody() {
  const t = useTranslations("Body");
  return (
    <Card label={t("emptyTitle")}>
      <h3 className="text-lg font-bold" style={{ color: "var(--text)" }}>{t("emptyTitle")}</h3>
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("emptyBody")}</p>
      <PrivacyLine>{t("emptyPrivacy")}</PrivacyLine>
      <NewMeasureLink />
    </Card>
  );
}

function ChartCard({ settings, snapshots }: { settings: BodySettingsResponse; snapshots: BodySnapshot[] }) {
  const t = useTranslations("Body");
  const locale = useUiLocale();
  const token = useBodyToken();
  const display = settings.settings.weight_display;
  const metrics = useMemo(() => {
    const seen = new Set<BodyMetric>(snapshots.flatMap((snapshot) => recordedMetrics(snapshot)));
    if (display === "hidden") seen.add("weight");
    return METRICS.filter((metric) => seen.has(metric));
  }, [snapshots, display]);
  const [picked, setPicked] = useState<BodyMetric | null>(null);
  const [range, setRange] = useState<BodyRange>("3m");
  const metric = picked && metrics.includes(picked) ? picked : (metrics[0] ?? null);
  const series = useQuery({
    queryKey: [...BODY_KEY, "series", metric, range],
    enabled: Boolean(token && metric),
    queryFn: () => fetchBodySeries(token!, metric!, range),
  });
  if (!metric) return null;
  const label = t(key("metric", metric));

  return (
    <Card label={t("chartLabel")}>
      {series.isPending ? (
        <LoadingLine />
      ) : series.isError ? (
        <QueryProblem error={series.error} onRetry={() => void series.refetch()} />
      ) : (
        <SeriesChart
          display={series.data.display}
          points={series.data.points}
          trend={series.data.trend}
          shape={series.data.shape}
          unit={series.data.unit}
          label={label}
          rangeLabel={t(key("rangeLong", range))}
          locale={locale}
          hiddenNote={
            <>
              {t("chartHiddenBody")}{" "}
              <Link href="/me/settings#journal-sections" className="font-semibold underline">{t("changeInSettings")}</Link>
            </>
          }
        />
      )}
      <div role="group" aria-label={t("metricsLabel")} className="flex flex-wrap gap-1.5">
        {metrics.map((item) => (
          <Chip key={item} selected={item === metric} onClick={() => setPicked(item)}>
            {t(key("metric", item))}
          </Chip>
        ))}
      </div>
      <div role="group" aria-label={t("rangeLabel")} className="flex flex-wrap gap-1.5">
        {RANGES.map((item) => (
          <Chip key={item} selected={item === range} onClick={() => setRange(item)}>
            {t(key("range", item))}
          </Chip>
        ))}
      </div>
    </Card>
  );
}

function CompareCard({ settings, snapshots }: { settings: BodySettingsResponse; snapshots: BodySnapshot[] }) {
  const t = useTranslations("Body");
  const locale = useUiLocale();
  const [sharing, setSharing] = useState(false);
  const pair = defaultComparePair(snapshots);
  if (!pair) return null;
  const from = snapshots.find((snapshot) => snapshot.id === pair.from)!;
  const to = snapshots.find((snapshot) => snapshot.id === pair.to)!;
  const poses = sharedPoses(from, to);
  const pose = poses[0] ?? "front";
  const dates = dateFormat(locale);
  const blur = settings.settings.blur_photos;

  return (
    <Card label={t("compareTitle")}>
      <div className="flex items-center justify-between gap-2">
        <Eyebrow>{t("compareTitle")}</Eyebrow>
        <span className="flex items-center gap-2">
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {t("compareRange", { from: dates.day(from.taken_at), to: dates.day(to.taken_at) })}
          </span>
          {poses.length ? <IconButton label={t("shareAria")} onClick={() => setSharing(true)}><ShareIcon /></IconButton> : null}
        </span>
      </div>
      {poses.length ? (
        <div className="grid grid-cols-2 gap-1.5">
          <BodyPhotoView photo={from.photos.find((photo) => photo.pose === pose)} blur={blur} label={dates.day(from.taken_at)} size="thumb" className="aspect-[3/4]" />
          <BodyPhotoView photo={to.photos.find((photo) => photo.pose === pose)} blur={blur} label={dates.day(to.taken_at)} size="thumb" className="aspect-[3/4]" />
        </div>
      ) : (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("compareNoPhotos")}</p>
      )}
      <PrivacyLine>{t("photosPrivate")}</PrivacyLine>
      <Link
        href={`/journal/body/compare?from=${encodeURIComponent(pair.from)}&to=${encodeURIComponent(pair.to)}`}
        className="text-sm font-semibold"
        style={{ color: "var(--primary)" }}
      >
        {t("openCompare")}
      </Link>
      {sharing ? <ShareBeforeAfterDialog snapshots={snapshots} fromId={pair.from} toId={pair.to} onClose={() => setSharing(false)} /> : null}
    </Card>
  );
}

function SnapshotsCard({ settings, snapshots }: { settings: BodySettingsResponse; snapshots: BodySnapshot[] }) {
  const t = useTranslations("Body");
  return (
    <Card label={t("snapshotsTitle")}>
      <Eyebrow>{t("snapshotsTitle")}</Eyebrow>
      <ul className="flex flex-col gap-3">
        {snapshots.map((snapshot, index) => (
          <SnapshotRow key={snapshot.id} snapshot={snapshot} previous={snapshots[index + 1]} settings={settings} />
        ))}
      </ul>
    </Card>
  );
}

export function snapshotSummary(
  snapshot: BodySnapshot,
  settings: Pick<BodySettingsResponse, "catalog">,
  locale: string,
  t: (key: string, values?: Record<string, string | number>) => string,
) {
  const parts = summaryMetrics(snapshot).map(({ metric, value }) =>
    t("summaryPart", { metric: t(key("metricShort", metric)), value: formatMetric(value, unitOf(metric, settings.catalog, snapshot.units), locale) }),
  );
  if (snapshot.photo_count) parts.push(t("photoCount", { count: snapshot.photo_count }));
  const summary = parts.join(" · ") || t("summaryEmpty");
  // ADR-161: a Garmin scale's weigh-in says where it came from.
  return snapshot.source === "garmin" ? [summary, t("fromGarmin")].join(" · ") : summary;
}

function SnapshotRow({ snapshot, previous, settings }: { snapshot: BodySnapshot; previous?: BodySnapshot; settings: BodySettingsResponse }) {
  const t = useTranslations("Body");
  const locale = useUiLocale();
  const change = snapshotChange(snapshot, previous);
  const thumb = snapshot.photos.find((photo) => photo.status === "ready") ?? snapshot.photos[0];
  const dates = dateFormat(locale);
  return (
    <li className="flex items-center gap-3" data-testid="body-snapshot">
      <div className="h-12 w-10 shrink-0">
        <BodyPhotoView photo={thumb} blur={settings.settings.blur_photos} label="" size="thumb" className="h-12 w-10" />
      </div>
      <Link href={`/journal/body/${snapshot.id}`} className="min-w-0 flex-1">
        <b className="block text-sm" style={{ color: "var(--text)" }}>{dates.dayYear(snapshot.taken_at)}</b>
        <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>{snapshotSummary(snapshot, settings, locale, t)}</span>
        <span className="block text-[11px]" style={{ color: "var(--dim)" }}>{t(key("visibilityShort", snapshot.visibility))}</span>
      </Link>
      {change ? <DeltaBadge delta={change.delta} unit={unitOf(change.metric, settings.catalog, snapshot.units)} locale={locale} /> : null}
    </li>
  );
}
