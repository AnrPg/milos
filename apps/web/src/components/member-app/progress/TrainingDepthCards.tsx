"use client";

import Link from "next/link";
import { useFormatter, useTranslations } from "next-intl";

import type { DepthCoverage, DepthLoad, DepthQualities } from "@/api/training-depth";
import { ClientCard, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { formatDay } from "@/components/client/format";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { atlasHref, COVERAGE_LEVELS, type CoverageLevel } from "@/lib/anatomy/atlas";
import {
  formatRatio,
  isLoadBand,
  loadBars,
  qualityScores,
  radarPoint,
  radarPolygon,
  topQualities,
  type LoadBand,
} from "@/lib/progress/training-depth";

/**
 * The three depth slots of Πρόοδος (ADR-165), in a fixed order: Μυϊκή
 * κάλυψη, Ποιότητες, Φορτίο. Each card always keeps its slot: loading,
 * a problem and «no data» render inside it. Shared by the member's Πρόοδος
 * and the coach's view of a client (`audience="coach"`: no atlas links, the
 * atlas is the member's own screen).
 */

type Section<T> = { data: T | null | undefined; pending: boolean; error: unknown; onRetry: () => void };

const LEVEL_COLOR: Record<CoverageLevel, string> = {
  none: "var(--border)",
  low: "var(--anatomy-heat-low)",
  medium: "var(--anatomy-heat-medium)",
  high: "var(--anatomy-heat-high)",
};

function level(value: unknown): CoverageLevel {
  return (COVERAGE_LEVELS as readonly string[]).includes(String(value)) ? (value as CoverageLevel) : "none";
}

function SlotState<T>({ section, children }: { section: Section<T>; children: (data: T) => React.ReactNode }) {
  const t = useTranslations("Depth");
  if (section.pending) return <LoadingLine />;
  if (section.error) return <QueryProblem error={section.error} onRetry={section.onRetry} />;
  if (!section.data) return <EmptyLine>{t("noData")}</EmptyLine>;
  return <>{children(section.data)}</>;
}

function Note({ children }: { children: React.ReactNode }) {
  return <p className="mt-3 self-stretch text-xs" style={{ color: "var(--dim)" }}>{children}</p>;
}

/** No workouts behind it yet: a member's Πρόοδος hides such a card (ANR 2026-10-24). */
export const depthEmpty = {
  coverage: (coverage: DepthCoverage | undefined) => !coverage?.sessions,
  qualities: (qualities: DepthQualities | undefined) =>
    !qualities?.sessions || qualityScores(qualities.qualities).every((row) => row.score === 0),
  load: (load: DepthLoad | undefined) => !load || (!load.unrated_sessions && loadBars(load.weeks).every((bar) => bar.load === 0)),
};

/** Whether a section is shown: always for the coach, for the member only once it holds something. */
function shown<T>(section: Section<T>, hideEmpty: boolean, empty: (data: T | undefined) => boolean): boolean {
  if (!hideEmpty) return true;
  if (section.error) return true;
  return !section.pending && !empty(section.data ?? undefined);
}

export function TrainingDepthCards({
  coverage,
  qualities,
  load,
  audience = "member",
  hideEmpty = false,
}: {
  coverage: Section<DepthCoverage>;
  qualities: Section<DepthQualities>;
  load: Section<DepthLoad>;
  audience?: "member" | "coach";
  hideEmpty?: boolean;
}) {
  const showCoverage = shown(coverage, hideEmpty, depthEmpty.coverage);
  const showQualities = shown(qualities, hideEmpty, depthEmpty.qualities);
  const showLoad = shown(load, hideEmpty, depthEmpty.load);
  if (!showCoverage && !showQualities && !showLoad) return null;
  return (
    <div className="flex flex-col gap-4" data-testid="training-depth">
      {showCoverage ? <CoverageCard section={coverage} audience={audience} /> : null}
      {showQualities || showLoad ? (
        <div className="grid gap-4 md:grid-cols-2">
          {showQualities ? <QualitiesCard section={qualities} /> : null}
          {showLoad ? <LoadCard section={load} /> : null}
        </div>
      ) : null}
    </div>
  );
}

function CoverageCard({ section, audience }: { section: Section<DepthCoverage>; audience: "member" | "coach" }) {
  const t = useTranslations("Depth");
  return (
    <ClientCard
      id="muscle-coverage"
      title={t("coverage.title")}
      aside={
        audience === "member" ? (
          <Link href={atlasHref()} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("coverage.atlas")}
          </Link>
        ) : null
      }
    >
      <SlotState section={section}>{(coverage) => <CoverageBody coverage={coverage} audience={audience} />}</SlotState>
    </ClientCard>
  );
}

function CoverageBody({ coverage, audience }: { coverage: DepthCoverage; audience: "member" | "coach" }) {
  const t = useTranslations("Depth");
  const locale = useUiLocale();
  if (!coverage.sessions) return <EmptyLine>{t("noData")}</EmptyLine>;
  const balance = coverage.balance;
  return (
    <div className="flex flex-col gap-3">
      <GroupRow label={t("coverage.most")} empty={t("coverage.noneMost")} groups={coverage.most ?? []} audience={audience} />
      <GroupRow label={t("coverage.least")} empty={t("coverage.noneLeast")} groups={coverage.least ?? []} audience={audience} />
      <dl className="grid grid-cols-1 gap-2 min-[420px]:grid-cols-2">
        <Ratio label={t("coverage.pushPull")} value={formatRatio(balance?.push_pull_ratio, locale)} />
        <Ratio label={t("coverage.quadHam")} value={formatRatio(balance?.quad_ham_ratio, locale)} />
      </dl>
      <Note>{t("coverage.note")}</Note>
    </div>
  );
}

function GroupRow({
  label,
  empty,
  groups,
  audience,
}: {
  label: string;
  empty: string;
  groups: DepthCoverage["most"];
  audience: "member" | "coach";
}) {
  const anatomy = useTranslations("Anatomy");
  const atlas = useTranslations("Atlas");
  return (
    <div>
      <p className="mb-1.5 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{label}</p>
      {groups.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{empty}</p>
      ) : (
        <ul className="flex flex-wrap gap-2">
          {groups.map((group) => {
            const name = anatomy.has(`muscle.${group.id}`) ? anatomy(`muscle.${group.id}`) : group.id;
            const groupLevel = level(group.level);
            const content = (
              <>
                <span aria-hidden="true" className="inline-block h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: LEVEL_COLOR[groupLevel] }} />
                <span>{name}</span>
                <span className="sr-only">{` · ${atlas("levelLine", { level: atlas(`level.${groupLevel}`) })}`}</span>
              </>
            );
            const style = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };
            return (
              <li key={group.id}>
                {audience === "member" ? (
                  <Link href={atlasHref(group.id)} className="inline-flex min-h-11 items-center gap-1.5 rounded-full px-3 text-sm" style={style}>
                    {content}
                  </Link>
                ) : (
                  <span className="inline-flex min-h-11 items-center gap-1.5 rounded-full px-3 text-sm" style={style}>
                    {content}
                  </span>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function Ratio({ label, value }: { label: string; value: string | null }) {
  const t = useTranslations("Depth");
  return (
    <div className="rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)" }}>
      <dt className="text-xs" style={{ color: "var(--dim)" }}>{label}</dt>
      <dd className="mt-0.5 text-base font-semibold tabular-nums" style={{ color: value ? "var(--text)" : "var(--dim)" }}>
        {value ? <bdi>{value}</bdi> : t("coverage.ratioMissing")}
      </dd>
    </div>
  );
}

function QualitiesCard({ section }: { section: Section<DepthQualities> }) {
  const t = useTranslations("Depth");
  return (
    <ClientCard id="qualities" title={t("qualities.title")}>
      <SlotState section={section}>{(qualities) => <QualitiesBody qualities={qualities} />}</SlotState>
    </ClientCard>
  );
}

const RADAR_SIZE = 220;
const RADAR_CENTER = RADAR_SIZE / 2;
const RADAR_RADIUS = 72;
// Room either side for the axis labels («Coordination», «Ευκινησία»).
const RADAR_PAD = 48;

function QualitiesBody({ qualities }: { qualities: DepthQualities }) {
  const t = useTranslations("Depth");
  const anatomy = useTranslations("Anatomy");
  const rows = qualityScores(qualities.qualities);
  if (!qualities.sessions || rows.every((row) => row.score === 0)) return <EmptyLine>{t("noData")}</EmptyLine>;

  const name = (id: string) => anatomy(`quality.${id}`);
  const most = topQualities(rows, "sets", 2);
  const felt = topQualities(rows, "felt", 2);
  const summary = t("qualities.most", { qualities: most.map(name).join(", ") });

  return (
    <div className="flex flex-col items-center gap-2">
      <svg
        viewBox={`${-RADAR_PAD} 0 ${RADAR_SIZE + RADAR_PAD * 2} ${RADAR_SIZE}`}
        className="h-auto w-full max-w-[340px]"
        role="img"
        aria-label={`${t("qualities.title")}: ${summary}`}
      >
        {[0.25, 0.5, 0.75, 1].map((ring) => (
          <polygon
            key={ring}
            points={radarPolygon(rows.map(() => ring), RADAR_CENTER, RADAR_RADIUS)}
            fill="none"
            stroke="var(--border)"
            strokeWidth={ring === 1 ? 1 : 0.6}
          />
        ))}
        {rows.map((row, index) => {
          const [x, y] = radarPoint(index, rows.length, 1, RADAR_CENTER, RADAR_RADIUS);
          return <line key={row.id} x1={RADAR_CENTER} y1={RADAR_CENTER} x2={x} y2={y} stroke="var(--border)" strokeWidth={0.6} />;
        })}
        <polygon
          points={radarPolygon(rows.map((row) => Math.max(row.score, 0.03)), RADAR_CENTER, RADAR_RADIUS)}
          fill="color-mix(in srgb, var(--primary) 28%, transparent)"
          stroke="var(--primary)"
          strokeWidth={1.6}
          strokeLinejoin="round"
        />
        {rows.map((row, index) => {
          const [x, y] = radarPoint(index, rows.length, 1.24, RADAR_CENTER, RADAR_RADIUS);
          const anchor = Math.abs(x - RADAR_CENTER) < 4 ? "middle" : x > RADAR_CENTER ? "start" : "end";
          return (
            <text key={row.id} x={x} y={y} textAnchor={anchor} dominantBaseline="middle" fontSize={9.5} fill="var(--text-soft)">
              {t(`qualities.short.${row.id}`)}
            </text>
          );
        })}
      </svg>
      <ul className="sr-only">
        {rows.map((row) => (
          <li key={row.id}>{t("qualities.row", { quality: name(row.id), sets: row.sets })}</li>
        ))}
      </ul>
      <p className="self-start text-sm" style={{ color: "var(--text)" }}>{summary}</p>
      {felt.length > 0 ? (
        <p className="self-start text-sm" style={{ color: "var(--muted)" }}>{t("qualities.felt", { qualities: felt.map(name).join(", ") })}</p>
      ) : null}
      <Note>{t("qualities.note")}</Note>
    </div>
  );
}

const BAND_STYLE: Record<LoadBand, { background: string; color: string }> = {
  below: { background: "var(--panel-muted)", color: "var(--text-soft)" },
  steady: { background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--text)" },
  above: { background: "color-mix(in srgb, var(--warning) 18%, transparent)", color: "var(--text)" },
  well_above: { background: "color-mix(in srgb, var(--warning) 30%, transparent)", color: "var(--text)" },
};

function LoadCard({ section }: { section: Section<DepthLoad> }) {
  const t = useTranslations("Depth");
  return (
    <ClientCard id="training-load" title={t("load.title")}>
      <SlotState section={section}>{(load) => <LoadBody load={load} />}</SlotState>
    </ClientCard>
  );
}

function LoadBody({ load }: { load: DepthLoad }) {
  const t = useTranslations("Depth");
  const format = useFormatter();
  const locale = useUiLocale();
  const bars = loadBars(load.weeks);
  const band = isLoadBand(load.band) ? load.band : null;
  const hasLoad = bars.some((bar) => bar.load > 0);
  const shortDate = (day: string) => formatDay(day, locale, { weekday: undefined, year: undefined, month: "short" });

  return (
    <div className="flex flex-col gap-3">
      {load.sufficient && band && typeof load.ratio === "number" ? (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-base font-semibold" style={{ color: "var(--text)" }}>
            {t("load.ratio", { ratio: format.number(load.ratio, { maximumFractionDigits: 1, minimumFractionDigits: 1 }) })}
          </p>
          <span className="rounded-full px-3 py-1 text-xs font-semibold" style={BAND_STYLE[band]} data-testid="load-band">
            {t(`load.band.${band}`)}
          </span>
        </div>
      ) : (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("load.insufficient")}</p>
      )}
      {hasLoad ? (
        <>
          <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("load.weeks")}</p>
          <ol className="flex h-24 items-end gap-1" aria-label={t("load.weeks")}>
            {bars.map((bar) => (
              <li
                key={bar.week_start}
                className="flex h-full min-w-0 flex-1 flex-col justify-end"
                aria-label={t("load.weekOf", { date: shortDate(bar.week_start), load: bar.load })}
              >
                <span
                  aria-hidden="true"
                  className="w-full rounded-t-md"
                  style={{ height: `${Math.max(bar.percent, bar.load > 0 ? 4 : 1)}%`, background: bar.load > 0 ? "var(--primary)" : "var(--border)" }}
                />
              </li>
            ))}
          </ol>
        </>
      ) : null}
      {load.unrated_sessions ? <p className="text-xs" style={{ color: "var(--muted)" }}>{t("load.unrated", { count: load.unrated_sessions })}</p> : null}
      <Note>{t("load.note")}</Note>
    </div>
  );
}
