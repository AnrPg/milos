"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { atlasNodeExercisesKey, fetchAtlasNodeExercises, fetchMyAtlas, myAtlasKey, type AtlasNodeExercise, type MyAtlas } from "@/api/atlas";
import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { ClientPage, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";
import { Segmented } from "@/components/wod-goals/GoalChips";
import {
  aboutNodeId,
  ATLAS_RANGES,
  atlasChildren,
  atlasHref,
  atlasPath,
  coverageLevel,
  coverageSets,
  DEFAULT_ATLAS_RANGE,
  exploreHighlights,
  feltCount,
  heatHighlights,
  indexCoverage,
  type AtlasMode,
  type AtlasRange,
  type CoverageIndex,
  type CoverageLevel,
} from "@/lib/anatomy/atlas";
import { childrenOf, isMuscleNodeId, muscleNode, type MuscleNodeId } from "@/lib/anatomy/taxonomy";

const LEVEL_COLOR: Record<CoverageLevel, string> = {
  none: "var(--border)",
  low: "var(--anatomy-heat-low)",
  medium: "var(--anatomy-heat-medium)",
  high: "var(--anatomy-heat-high)",
};

const EXERCISES_SHOWN = 5;

/**
 * Ημερολόγιο › Πρόοδος › Άτλαντας (ADR-164, vision §7.6): the rotatable body
 * with three levels (region › group › head), what each muscle does, the
 * member's own sets in the range with a coverage level, what they felt, and
 * the exercises that train it with the gym's videos. «Η κάλυψή μου» paints
 * the body by recent volume. `?node=` opens it on a node (WOD goals,
 * Πρόοδος › Μυϊκή κάλυψη).
 */
export function AtlasScreen() {
  const t = useTranslations("Atlas");
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;

  const initial = searchParams.get("node");
  const [selected, setSelected] = useState<MuscleNodeId | null>(initial && isMuscleNodeId(initial) ? initial : null);
  const [mode, setMode] = useState<AtlasMode>("explore");
  const [range, setRange] = useState<AtlasRange>(DEFAULT_ATLAS_RANGE);

  const atlas = useQuery({
    queryKey: [...myAtlasKey(range), token],
    enabled: Boolean(token),
    queryFn: () => fetchMyAtlas(token!, range),
    placeholderData: (previous) => previous,
  });
  const index = useMemo(() => indexCoverage(atlas.data?.nodes), [atlas.data]);
  const highlights = useMemo(
    () => (mode === "heat" ? heatHighlights(index, selected) : exploreHighlights(selected)),
    [index, mode, selected],
  );

  const select = (id: MuscleNodeId | null) => {
    setSelected(id);
    router.replace(atlasHref(id), { scroll: false });
  };

  return (
    <ClientPage
      title={t("title")}
      actions={
        <Link href="/journal/progress" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
          {t("back")}
        </Link>
      }
    >
      <div className="flex flex-col gap-3">
        <Segmented<AtlasMode>
          ariaLabel={t("mode.label")}
          value={mode}
          onChange={setMode}
          options={[
            { value: "explore", label: t("mode.explore") },
            { value: "heat", label: t("mode.heat") },
          ]}
        />
        <div role="group" aria-label={t("range.label")} className="flex gap-2">
          {ATLAS_RANGES.map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={range === value}
              onClick={() => setRange(value)}
              className="min-h-9 rounded-full px-3 text-xs font-semibold"
              style={{
                background: range === value ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
                border: `1px solid ${range === value ? "var(--primary)" : "var(--border)"}`,
                color: range === value ? "var(--text)" : "var(--text-soft)",
              }}
            >
              {t(`range.${value}`)}
            </button>
          ))}
        </div>
      </div>

      <div className="grid items-start gap-4 md:grid-cols-2">
        <div className="flex flex-col gap-2" data-testid="atlas-figure">
          <AnatomyFigure
            highlights={highlights}
            view="both"
            interactive
            size="full"
            // On a phone the panel sits under the figure; keep it in reach.
            className="max-md:h-[48vh]"
            focus={selected}
            onPick={(id) => select(id)}
          />
          {mode === "heat" ? <HeatLegend /> : null}
        </div>
        <section
          aria-live="polite"
          data-testid="atlas-panel"
          className="flex min-w-0 flex-col gap-4 rounded-2xl p-4"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <Breadcrumb selected={selected} onSelect={select} />
          {atlas.isPending && token ? (
            <LoadingLine />
          ) : atlas.isError ? (
            <QueryProblem error={atlas.error} onRetry={() => void atlas.refetch()} />
          ) : (
            <NodePanel selected={selected} index={index} atlas={atlas.data ?? null} range={range} onSelect={select} token={token} />
          )}
        </section>
      </div>
    </ClientPage>
  );
}

function HeatLegend() {
  const t = useTranslations("Atlas");
  return (
    <div className="flex flex-col gap-1">
      <ul className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs" style={{ color: "var(--text-soft)" }}>
        {(["low", "medium", "high"] as const).map((level) => (
          <li key={level} className="flex items-center gap-1.5">
            <LevelDot level={level} />
            {t(`level.${level}`)}
          </li>
        ))}
      </ul>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("legendNote")}</p>
    </div>
  );
}

function LevelDot({ level }: { level: CoverageLevel }) {
  return <span aria-hidden="true" className="inline-block h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: LEVEL_COLOR[level] }} />;
}

function Breadcrumb({ selected, onSelect }: { selected: MuscleNodeId | null; onSelect: (id: MuscleNodeId | null) => void }) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const path = atlasPath(selected);
  const crumbs: Array<{ id: MuscleNodeId | null; label: string }> = [
    { id: null, label: t("crumbs.body") },
    ...path.map((node) => ({ id: node.id, label: anatomy(`muscle.${node.id}`) })),
  ];
  return (
    <nav aria-label={t("crumbs.label")}>
      <ol className="flex flex-wrap items-center gap-1 text-sm">
        {crumbs.map((crumb, position) => {
          const last = position === crumbs.length - 1;
          return (
            <li key={crumb.id ?? "body"} className="flex items-center gap-1">
              {last ? (
                <span aria-current="page" className="font-bold" style={{ color: "var(--text)" }}>{crumb.label}</span>
              ) : (
                <button type="button" onClick={() => onSelect(crumb.id)} className="font-semibold underline-offset-2 hover:underline" style={{ color: "var(--primary)" }}>
                  {crumb.label}
                </button>
              )}
              {last ? null : <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

function NodePanel({
  selected,
  index,
  atlas,
  range,
  onSelect,
  token,
}: {
  selected: MuscleNodeId | null;
  index: CoverageIndex;
  atlas: MyAtlas | null;
  range: AtlasRange;
  onSelect: (id: MuscleNodeId | null) => void;
  token: string | null;
}) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const node = muscleNode(selected);
  const sessions = atlas?.sessions ?? 0;
  const unrecognized = atlas?.exercises?.unrecognized ?? 0;

  if (!node) {
    return (
      <>
        <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("body.title")}</h2>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("body.hint")}</p>
        {sessions === 0 ? <EmptyNote>{t("noData")}</EmptyNote> : null}
        <ChildList ids={atlasChildren(null).map((child) => child.id)} index={index} onSelect={onSelect} label={t("regions")} />
        {unrecognized > 0 ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("unrecognized", { count: unrecognized })}</p>
        ) : null}
      </>
    );
  }

  const aboutId = aboutNodeId(node.id);
  const heads = node.kind === "region" ? [] : node.kind === "group" ? childrenOf(node.id) : childrenOf(node.groupId ?? "");
  return (
    <>
      <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }} data-testid="atlas-node-title">
        {anatomy(`muscle.${node.id}`)}
      </h2>
      {aboutId ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{anatomy(`about.${aboutId}`)}</p> : null}
      {heads.length > 0 ? (
        <div className="flex flex-col gap-1">
          <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("heads")}</p>
          <div className="flex flex-wrap gap-1.5">
            {heads.map((head) => (
              <button
                key={head.id}
                type="button"
                aria-pressed={head.id === node.id}
                onClick={() => onSelect(head.id === node.id ? head.groupId : head.id)}
                className="inline-flex min-h-9 items-center gap-1.5 rounded-full px-3 text-xs font-semibold"
                style={{
                  background: head.id === node.id ? "color-mix(in srgb, var(--primary) 18%, var(--panel))" : "var(--panel-raised, var(--card))",
                  border: `1px solid ${head.id === node.id ? "var(--primary)" : "var(--border)"}`,
                  color: "var(--text)",
                }}
              >
                <LevelDot level={coverageLevel(index, head.id)} />
                {anatomy(`muscle.${head.id}`)}
              </button>
            ))}
          </div>
        </div>
      ) : null}
      <YourSets nodeId={node.id} index={index} range={range} sessions={sessions} />
      {node.kind === "region" ? (
        <ChildList ids={childrenOf(node.id).map((child) => child.id)} index={index} onSelect={onSelect} label={t("groups")} />
      ) : (
        <NodeExercises nodeId={node.id} token={token} />
      )}
    </>
  );
}

function YourSets({ nodeId, index, range, sessions }: { nodeId: MuscleNodeId; index: CoverageIndex; range: AtlasRange; sessions: number }) {
  const t = useTranslations("Atlas");
  const format = useFormatter();
  const level = coverageLevel(index, nodeId);
  const sets = coverageSets(index, nodeId);
  const felt = feltCount(index, nodeId);
  const top = index.get(nodeId)?.top_exercises ?? [];
  const perWeek = index.get(nodeId)?.per_week ?? 0;
  const number = (value: number) => format.number(value, { maximumFractionDigits: 1 });

  return (
    <div className="flex flex-col gap-1.5 rounded-xl p-3" style={{ background: "var(--bg)" }} data-testid="atlas-your-sets">
      <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("yours", { range: t(`range.${range}`) })}</p>
      {sessions === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noData")}</p>
      ) : sets === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noneHere")}</p>
      ) : (
        <>
          <p className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("sets", { sets: number(sets) })}</span>
            <span className="inline-flex items-center gap-1.5 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              <LevelDot level={level} />
              {t("levelLine", { level: t(`level.${level}`) })}
            </span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("perWeek", { perWeek: number(perWeek) })}</span>
          </p>
          {top.length > 0 ? (
            <p className="text-xs" style={{ color: "var(--text-soft)" }}>
              {t("from", { exercises: format.list(top.map((exercise) => exercise.label ?? exercise.exercise_ref)) })}
            </p>
          ) : null}
        </>
      )}
      {felt > 0 ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("felt", { count: felt })}</p> : null}
    </div>
  );
}

function ChildList({ ids, index, onSelect, label }: { ids: MuscleNodeId[]; index: CoverageIndex; onSelect: (id: MuscleNodeId) => void; label: string }) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const format = useFormatter();
  return (
    <ul aria-label={label} className="flex flex-col gap-1.5">
      {ids.map((id) => {
        const level = coverageLevel(index, id);
        const sets = coverageSets(index, id);
        return (
          <li key={id}>
            <button
              type="button"
              onClick={() => onSelect(id)}
              className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start"
              style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
            >
              <LevelDot level={level} />
              <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{anatomy(`muscle.${id}`)}</span>
              <span className="shrink-0 text-xs" style={{ color: "var(--text-soft)" }}>
                {sets > 0 ? t("sets", { sets: format.number(sets, { maximumFractionDigits: 1 }) }) : t(`level.${level}`)}
              </span>
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function NodeExercises({ nodeId, token }: { nodeId: MuscleNodeId; token: string | null }) {
  const t = useTranslations("Atlas");
  const [expanded, setExpanded] = useState(false);
  const query = useQuery({
    queryKey: [...atlasNodeExercisesKey(nodeId), token],
    enabled: Boolean(token),
    queryFn: () => fetchAtlasNodeExercises(token!, nodeId),
    staleTime: 5 * 60_000,
    retry: false,
  });
  const exercises: AtlasNodeExercise[] = Array.isArray(query.data?.exercises) ? query.data.exercises : [];
  const shown = expanded ? exercises : exercises.slice(0, EXERCISES_SHOWN);

  return (
    <section className="flex flex-col gap-2" data-testid="atlas-exercises">
      <h3 className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("exercises.title")}</h3>
      {query.isPending && token ? (
        <LoadingLine />
      ) : query.isError ? (
        <EmptyNote>{t("exercises.unavailable")}</EmptyNote>
      ) : exercises.length === 0 ? (
        <EmptyNote>{t("exercises.empty")}</EmptyNote>
      ) : (
        <>
          <ul className="flex flex-col gap-1.5">
            {shown.map((exercise) => (
              <li
                key={exercise.exercise_ref}
                className="flex flex-col gap-1 rounded-xl px-3 py-2"
                style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
              >
                <span className="flex items-center gap-2">
                  <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{exercise.label}</span>
                  <span className="shrink-0 text-[11px] font-semibold" style={{ color: "var(--dim)" }}>{t(`exercises.role.${exercise.role}`)}</span>
                </span>
                {(exercise.videos ?? []).map((video) => (
                  <a
                    key={video.id}
                    href={video.video_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs font-semibold underline-offset-2 hover:underline"
                    style={{ color: "var(--primary)" }}
                  >
                    {t("exercises.video", { title: video.title })}
                  </a>
                ))}
              </li>
            ))}
          </ul>
          {exercises.length > EXERCISES_SHOWN ? (
            <button
              type="button"
              onClick={() => setExpanded((value) => !value)}
              className="self-start text-xs font-semibold"
              style={{ color: "var(--primary)" }}
            >
              {expanded ? t("exercises.less") : t("exercises.more", { count: exercises.length })}
            </button>
          ) : null}
        </>
      )}
    </section>
  );
}

function EmptyNote({ children }: { children: React.ReactNode }) {
  return (
    <p className="rounded-xl px-3 py-3 text-sm" style={{ background: "var(--panel-muted, var(--bg))", color: "var(--dim)" }}>
      {children}
    </p>
  );
}
