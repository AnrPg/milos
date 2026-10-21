"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BODY_KEY, fetchBodyComparison, type BodyCatalogEntry, type BodyComparison, type BodyPhoto, type BodyPose, type CompareMode } from "@/api/body";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { BodyPhotoView, Card, Chip, Eyebrow, PrivacyLine, dateFormat, key } from "@/components/body/BodyBits";
import { useBodySettings, useBodySnapshots, useBodyToken, useUpdateBodySettings } from "@/components/body/use-body";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { POSES, defaultComparePair, formatDelta, sharedPoses, toDeltaRows, unitOf } from "@/lib/body";

/**
 * Two photos of one pose on top of each other with a divider to drag
 * (board 13 q5), or side by side; the divider is a range input so it works
 * with keys too.
 */
export function CompareSlider({
  from,
  to,
  fromLabel,
  toLabel,
  mode,
  blur,
}: {
  from: BodyPhoto | null | undefined;
  to: BodyPhoto | null | undefined;
  fromLabel: string;
  toLabel: string;
  mode: CompareMode;
  blur: boolean;
}) {
  const t = useTranslations("Body");
  const [split, setSplit] = useState(50);
  const [revealed, setRevealed] = useState(!blur);

  if (mode === "side_by_side") {
    return (
      <div className="grid grid-cols-2 gap-2" data-testid="compare-side-by-side">
        <figure className="flex flex-col gap-1">
          <BodyPhotoView photo={from} blur={blur} label={fromLabel} className="aspect-[3/4]" />
          <figcaption className="text-center text-xs" style={{ color: "var(--dim)" }}>{fromLabel}</figcaption>
        </figure>
        <figure className="flex flex-col gap-1">
          <BodyPhotoView photo={to} blur={blur} label={toLabel} className="aspect-[3/4]" />
          <figcaption className="text-center text-xs" style={{ color: "var(--dim)" }}>{toLabel}</figcaption>
        </figure>
      </div>
    );
  }

  const fromUrl = from?.status === "ready" ? (from.feed_url ?? from.thumb_url) : null;
  const toUrl = to?.status === "ready" ? (to.feed_url ?? to.thumb_url) : null;
  if (!fromUrl || !toUrl) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("compareNoPhotos")}</p>;
  const hidden = !revealed;

  return (
    <div className="flex flex-col gap-2" data-testid="compare-slider">
      <div className="relative aspect-[3/4] w-full overflow-hidden rounded-xl" style={{ background: "var(--media)" }}>
        {/* eslint-disable-next-line @next/next/no-img-element -- short-lived presigned URL */}
        <img src={fromUrl} alt={fromLabel} className="absolute inset-0 h-full w-full object-cover" style={hidden ? { filter: "blur(18px)" } : undefined} draggable={false} />
        {/* eslint-disable-next-line @next/next/no-img-element -- short-lived presigned URL */}
        <img
          src={toUrl}
          alt={toLabel}
          className="absolute inset-0 h-full w-full object-cover"
          style={{ clipPath: `inset(0 0 0 ${split}%)`, ...(hidden ? { filter: "blur(18px)" } : {}) }}
          draggable={false}
        />
        <span aria-hidden="true" className="absolute inset-y-0 w-0.5" style={{ left: `${split}%`, background: "var(--on-media)" }} />
        <span className="absolute bottom-1.5 start-2 text-[11px] font-bold text-[var(--on-media)]">{fromLabel}</span>
        <span className="absolute bottom-1.5 end-2 text-[11px] font-bold text-[var(--on-media)]">{toLabel}</span>
        {hidden ? (
          <button
            type="button"
            onClick={() => setRevealed(true)}
            className="absolute inset-0 flex items-center justify-center text-xs font-bold text-[var(--on-media)]"
            aria-label={t("revealCompare")}
          >
            <span className="rounded-full px-2 py-1" style={{ background: "var(--media-control)" }}>{t("tapToShow")}</span>
          </button>
        ) : null}
      </div>
      <label className="flex items-center gap-2 text-xs" style={{ color: "var(--dim)" }}>
        <span className="sr-only">{t("dividerLabel")}</span>
        <input type="range" min={0} max={100} value={split} onChange={(event) => setSplit(Number(event.target.value))} className="w-full" aria-label={t("dividerLabel")} />
      </label>
    </div>
  );
}

export function DeltaList({ comparison, catalog, locale }: { comparison: BodyComparison; catalog: BodyCatalogEntry[]; locale: string }) {
  const t = useTranslations("Body");
  const rows = toDeltaRows(comparison.deltas);
  if (rows.length === 0) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("compareNoMetrics")}</p>;
  return (
    <dl className="flex flex-col" data-testid="compare-deltas">
      {rows.map((row) => (
        <div key={row.metric} className="flex justify-between gap-3 border-b py-2 text-sm last:border-b-0" style={{ borderColor: "var(--border)" }}>
          <dt style={{ color: "var(--text)" }}>{t(key("metric", row.metric))}</dt>
          <dd className="font-semibold tabular-nums" style={{ color: "var(--text)" }}>
            {row.kind === "number"
              ? formatDelta(row.delta, unitOf(row.metric, catalog, comparison.units), locale)
              : row.direction
                ? t(key("trend", row.direction))
                : t("trendNotYet")}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * Σύγκριση (board 13 q5): two snapshots (first and latest by default), pose
 * tabs, the slider or side by side (remembered in compare_mode), and the
 * change of each metric, in words when weight shows as a trend. Nothing can
 * be shared from here.
 */
export function ComparePage() {
  const t = useTranslations("Body");
  const locale = useUiLocale();
  const token = useBodyToken();
  const params = useSearchParams();
  const settings = useBodySettings();
  const snapshots = useBodySnapshots();
  const update = useUpdateBodySettings();
  const list = useMemo(() => snapshots.data?.pages.flatMap((page) => page.snapshots) ?? [], [snapshots.data]);
  const pair = defaultComparePair(list);
  const [from, setFrom] = useState<string | null>(params.get("from"));
  const [to, setTo] = useState<string | null>(params.get("to"));
  const fromId = from ?? (pair && pair.from !== to ? pair.from : (list.find((item) => item.id !== to)?.id ?? null));
  const toId = to ?? pair?.to ?? null;
  const [modeOverride, setModeOverride] = useState<CompareMode | null>(null);
  const [pickedPose, setPose] = useState<BodyPose | null>(null);
  const comparison = useQuery({
    queryKey: [...BODY_KEY, "compare", fromId, toId],
    enabled: Boolean(token && fromId && toId && fromId !== toId),
    queryFn: () => fetchBodyComparison(token!, fromId!, toId!),
  });

  if (settings.isPending || snapshots.isPending) return <LoadingLine />;
  if (settings.isError) return <QueryProblem error={settings.error} onRetry={() => void settings.refetch()} />;
  if (list.length < 2) {
    return (
      <Card label={t("compareTitle")}>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("compareNeedTwo")}</p>
        <Link href="/journal/body" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>← {t("title")}</Link>
      </Card>
    );
  }

  const dates = dateFormat(locale);
  const mode = modeOverride ?? settings.data.settings.compare_mode;
  const data = comparison.data;
  const poses = data ? sharedPoses(data.from, data.to) : [];
  const pose = pickedPose && poses.includes(pickedPose) ? pickedPose : (poses[0] ?? null);

  function chooseMode(next: CompareMode) {
    setModeOverride(next);
    if (next !== settings.data?.settings.compare_mode) update.mutate({ compare_mode: next });
  }

  const picker = (label: string, value: string | null, onChange: (id: string) => void, exclude: string | null) => (
    <label className="flex flex-1 flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
      {label}
      <select
        value={value ?? ""}
        onChange={(event) => onChange(event.target.value)}
        className="min-h-11 rounded-xl px-3 text-sm"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {list
          .filter((item) => item.id !== exclude)
          .map((item) => (
            <option key={item.id} value={item.id}>{dates.dayYear(item.taken_at)}</option>
          ))}
      </select>
    </label>
  );

  return (
    <div className="flex flex-col gap-4">
      <div>
        <Link href="/journal/body" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>← {t("title")}</Link>
        <h2 className="mt-1 text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("compareTitle")}</h2>
      </div>
      <div className="flex gap-2">
        {picker(t("compareFrom"), fromId, setFrom, toId)}
        {picker(t("compareTo"), toId, setTo, fromId)}
      </div>

      {comparison.isPending ? (
        <LoadingLine />
      ) : comparison.isError ? (
        <QueryProblem error={comparison.error} onRetry={() => void comparison.refetch()} />
      ) : data ? (
        <>
          <Card label={t("photosLabel")}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div role="tablist" aria-label={t("posesLabel")} className="flex gap-1.5">
                {POSES.map((item) => (
                  <button
                    key={item}
                    type="button"
                    role="tab"
                    aria-selected={item === pose}
                    disabled={!poses.includes(item)}
                    onClick={() => setPose(item)}
                    className="min-h-9 rounded-full px-3 text-sm font-semibold disabled:opacity-40"
                    style={{
                      background: item === pose ? "var(--primary)" : "var(--panel-raised)",
                      color: item === pose ? "var(--bg)" : "var(--text)",
                      border: "1px solid var(--border)",
                    }}
                  >
                    {t(key("pose", item))}
                  </button>
                ))}
              </div>
              <div role="group" aria-label={t("compareModeLabel")} className="flex gap-1.5">
                <Chip selected={mode === "slider"} onClick={() => chooseMode("slider")}>{t("modeSlider")}</Chip>
                <Chip selected={mode === "side_by_side"} onClick={() => chooseMode("side_by_side")}>{t("modeSideBySide")}</Chip>
              </div>
            </div>
            {pose ? (
              <CompareSlider
                key={[pose, mode].join("-")}
                from={data.from.photos.find((photo) => photo.pose === pose)}
                to={data.to.photos.find((photo) => photo.pose === pose)}
                fromLabel={dates.day(data.from.taken_at)}
                toLabel={dates.day(data.to.taken_at)}
                mode={mode}
                blur={settings.data.settings.blur_photos}
              />
            ) : (
              <p className="text-sm" style={{ color: "var(--muted)" }}>{t("compareNoPhotos")}</p>
            )}
            <PrivacyLine>{t("photosPrivate")}</PrivacyLine>
          </Card>
          <Card label={t("compareChanges")}>
            <Eyebrow>{t("compareChanges")}</Eyebrow>
            <DeltaList comparison={data} catalog={settings.data.catalog} locale={locale} />
          </Card>
        </>
      ) : null}
    </div>
  );
}
