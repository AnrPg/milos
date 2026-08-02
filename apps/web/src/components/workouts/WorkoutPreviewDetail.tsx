"use client";






import {useUiTranslations} from "@/i18n/ui";
import { semanticLabel } from "@/i18n/presentation";
import { useState } from "react";

import { scaleLevelVar, translucent } from "@/lib/theme";

export type PreviewExercise = {
  id?: string;
  item_type?: "exercise" | "header";
  name: string;
  sets?: number | null;
  prescription_value?: number | null;
  prescription_unit?: string | null;
  load_value?: number | null;
  load_mode?: string | null;
  set_prescriptions?: Array<{
    set_index: number;
    prescription_value?: number | null;
    prescription_unit?: string | null;
    load_value?: number | null;
    load_mode?: string | null;
    note?: string | null;
  }> | null;
  load_progression?: {
    mode?: "linear" | "per_set";
    direction?: "increase" | "decrease";
    start_value?: number;
    start_mode?: string;
    step_value?: number;
    per_set_values?: number[];
  } | null;
  order?: number;
  superset_group_id?: string | null;
  alternating_group_id?: string | null;
  group_config?: { sets?: number | null; title?: string | null } | null;
  hr_zone?: number | null;
  tempo?: string | null;
  rest_seconds?: number | null;
  cluster_rest_seconds?: number | null;
  rest_pause_seconds?: number | null;
  pacing?: number | null;
  interval_assignment?: number | null;
  description?: string | null;
  note?: string | null;
  variations?: Array<{
    id?: string;
    description?: string | null;
    exercise_name_override?: string | null;
    sets?: number | null;
    prescription_value?: number | null;
    prescription_unit?: string | null;
    load_value?: number | null;
    load_mode?: string | null;
    set_prescriptions?: PreviewExercise["set_prescriptions"];
    load_progression?: PreviewExercise["load_progression"];
    excluded?: boolean;
    note?: string | null;
    scale_level?: { id?: string; slug?: string; label?: string; sort_order?: number } | null;
  }>;
};

export type PreviewSection = {
  id?: string;
  name: string;
  order?: number;
  scoreable?: boolean;
  score_config?: Record<string, unknown> | null;
  timer_config?: Record<string, unknown> | null;
  note?: string | null;
  exercises: PreviewExercise[];
};

type Props = {
  sections: PreviewSection[];
  initiallyExpanded?: boolean;
  activeScaleOverride?: string | null;
  hideScaleChips?: boolean;
};

type PreviewVariation = NonNullable<PreviewExercise["variations"]>[number];

type ResolvedExercise = PreviewExercise & {
  varied: boolean;
  variationLabel?: string;
  variationSlug?: string;
};

function resolveExercise(exercise: PreviewExercise, activeScale: string | null): ResolvedExercise | null {
  if (!activeScale) {
    return { ...exercise, varied: false };
  }

  const variation = (exercise.variations ?? []).find((item) => item.scale_level?.slug === activeScale);

  if (!variation) {
    return { ...exercise, varied: false };
  }

  if (variation.excluded) {
    return null;
  }

  return {
    ...exercise,
    name: variation.exercise_name_override ?? variation.description ?? exercise.name,
    sets: variation.sets ?? exercise.sets,
    prescription_value: variation.prescription_value ?? exercise.prescription_value,
    prescription_unit: variation.prescription_unit ?? exercise.prescription_unit,
    load_value: variation.load_value ?? exercise.load_value,
    load_mode: variation.load_mode ?? exercise.load_mode,
    set_prescriptions: variation.set_prescriptions ?? exercise.set_prescriptions,
    load_progression: variation.load_progression ?? exercise.load_progression,
    note: variation.note ?? exercise.note,
    varied: true,
    variationLabel: variation.scale_level?.label ?? variation.scale_level?.slug,
    variationSlug: variation.scale_level?.slug,
  };
}

function sectionScaleOptions(section: PreviewSection) {
  const scales = new Map<string, { slug: string; label: string; sortOrder: number }>();

  section.exercises.forEach((exercise) => {
    (exercise.variations ?? []).forEach((variation: PreviewVariation) => {
      const slug = variation.scale_level?.slug;
      if (!slug) return;

      scales.set(slug, {
        slug,
        label: variation.scale_level?.label ?? slug,
        sortOrder: variation.scale_level?.sort_order ?? 0,
      });
    });
  });

  return Array.from(scales.values()).sort((left, right) => {
    if (left.sortOrder !== right.sortOrder) return left.sortOrder - right.sortOrder;
    return left.label.localeCompare(right.label);
  });
}

function ExerciseRow({ exercise, groupColor }: { exercise: ResolvedExercise; groupColor?: string }) {
  const i18n = useUiTranslations();

  if (exercise.item_type === "header") {
    return (
      <li className="border-y px-2 py-2" style={{ borderColor: "var(--border-strong)" }}>
        <div className="text-xs font-bold uppercase" style={{ color: "var(--primary)" }}>
          {exercise.name}
        </div>
        {exercise.note ? (
          <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>
            {exercise.note}
          </p>
        ) : null}
      </li>
    );
  }

  function formatExtras(exercise: PreviewExercise): string[] {
    const extras: string[] = [];
    if (exercise.tempo) extras.push(i18n("tempoValue0e842308", {value0: exercise.tempo}));
    if (exercise.rest_seconds) extras.push(i18n("restValue0S0cde064", {value0: exercise.rest_seconds}));
    if (exercise.hr_zone) extras.push(i18n("hrZValue0defc7f9", {value0: exercise.hr_zone}));
    if (exercise.pacing) extras.push(i18n("paceValue0SRep5b31b72", {value0: exercise.pacing}));
    if (exercise.cluster_rest_seconds) extras.push(i18n("clusterValue0S3514326", {value0: exercise.cluster_rest_seconds}));
    if (exercise.rest_pause_seconds) extras.push(i18n("restValue0S0cde064", {value0: exercise.rest_pause_seconds}));
    if (exercise.interval_assignment) extras.push(`${i18n("interval011efcd")} ${exercise.interval_assignment}`);
    return extras;
  }

  function formatProgression(exercise: PreviewExercise): string | null {
    const progression = exercise.load_progression;
    if (!progression) return null;
    const direction = progression.direction === "decrease" ? i18n("progressiveLoadDecrease") : i18n("progressiveLoadIncrease");
    if (progression.mode === "per_set" && progression.per_set_values?.length) {
      return `${direction}: ${progression.per_set_values.join(" / ")}`;
    }
    const start = progression.start_value != null ? `${progression.start_value} ${progression.start_mode ?? ""}`.trim() : "";
    const step = progression.step_value != null ? `+${progression.step_value}` : "";
    return [direction, start, step].filter(Boolean).join(" · ");
  }

  function formatPrescription(exercise: PreviewExercise): string {
    const parts: string[] = [];

    if (exercise.set_prescriptions && exercise.set_prescriptions.length > 0) {
      const first = exercise.set_prescriptions[0];
      const differs = exercise.set_prescriptions.some(
        (set) =>
          set.prescription_value !== first?.prescription_value ||
          set.load_value !== first?.load_value ||
          set.load_mode !== first?.load_mode,
      );

      if (differs) {
        return exercise.set_prescriptions
          .map((set) => {
            const unit = semanticLabel(set.prescription_unit ?? "reps", i18n);
            const loadUnit = set.load_mode === "pct_1rm" ? i18n("percentOneRepMaxUnit") : i18n("kilogramsUnit");
            const load = set.load_value != null ? ` · ${set.load_value} ${loadUnit}` : "";
            return `${set.set_index}: ${set.prescription_value ?? "—"} ${unit}${load}`;
          })
          .join(" | ");
      }
    }
  
    if (!groupColor && exercise.sets && exercise.sets > 1) {
      parts.push(`${exercise.sets}×`);
    }
  
    if (exercise.prescription_value) {
      const unit = semanticLabel(exercise.prescription_unit ?? "reps", i18n);
      parts.push(i18n("value0Value1dca59cc", {value0: exercise.prescription_value, value1: unit}));
    }
  
    if (exercise.load_value && exercise.load_mode !== "bw") {
      const suffix = exercise.load_mode === "pct_1rm" ? i18n("percentOneRepMaxUnit") : i18n("kilogramsUnit");
      parts.push(i18n("value0Value1bd98b64", {value0: exercise.load_value, value1: suffix}));
    } else if (exercise.load_mode === "bw") {
      parts.push(i18n("bw4d64743"));
    }
  
    return parts.join(" ").trim();
  }

  const prescription = formatPrescription(exercise);
  const extras = formatExtras(exercise);
  const progression = formatProgression(exercise);
  const variationColor = scaleLevelVar(exercise.variationSlug ?? exercise.variationLabel);
  const displayName = exercise.name?.trim() || exercise.description?.trim() || i18n("exercise1091b7f");
  return (
    <li
      className="rounded-[1rem] px-4 py-3"
      style={{
        background: exercise.varied ? translucent(variationColor, 11) : "var(--panel-muted)",
        border: exercise.varied ? `1px solid ${translucent(variationColor, 32)}` : "1px solid var(--border)",
        boxShadow: groupColor
          ? `inset 3px 0 0 ${groupColor}`
          : exercise.varied
            ? `inset 3px 0 0 ${variationColor}`
            : "none",
      }}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <span className="text-sm font-semibold leading-5" style={{ color: "var(--text)" }}>
            {displayName}
          </span>
          {exercise.varied ? (
            <span
              className="ms-2 rounded-full px-2 py-0.5 align-middle text-[10px] font-bold uppercase tracking-[0.16em]"
              style={{ background: translucent(variationColor, 18), color: variationColor }}
            >
              {exercise.variationLabel ?? i18n("variation15920a4")}
            </span>
          ) : null}
        </div>
        {prescription ? (
          <span
            className="shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold"
            style={{
              background: exercise.varied ? translucent(variationColor, 18) : "var(--card)",
              color: exercise.varied ? variationColor : "var(--text-soft)",
            }}
          >
            {prescription}
          </span>
        ) : null}
      </div>
      {extras.length > 0 ? (
        <p className="mt-1.5 text-xs leading-5" style={{ color: "var(--dim)" }}>
          {extras.join(" · ")}
        </p>
      ) : null}
      {exercise.description ? (
        <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
          {exercise.description}
        </p>
      ) : null}
      {progression ? (
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
          {progression}
        </p>
      ) : null}
      {exercise.note ? (
        <p className="mt-1 text-xs italic" style={{ color: "var(--muted)" }}>
          {exercise.note}
        </p>
      ) : null}
    </li>
  );
}

type PresentedExercise =
  | { type: "exercise"; exercise: ResolvedExercise }
  | {
      type: "group";
      id: string;
      kind: "superset" | "alternating";
      sets: number | null;
      title: string | null;
      exercises: ResolvedExercise[];
    };

function presentExercises(exercises: ResolvedExercise[]): PresentedExercise[] {
  const rendered = new Set<string>();
  const result: PresentedExercise[] = [];

  for (const exercise of exercises) {
    const kind = exercise.superset_group_id ? "superset" : exercise.alternating_group_id ? "alternating" : null;
    const id = exercise.superset_group_id ?? exercise.alternating_group_id;
    if (!kind || !id) {
      result.push({ type: "exercise", exercise });
      continue;
    }
    if (rendered.has(id)) continue;
    rendered.add(id);
    const members = exercises.filter((item) =>
      kind === "superset" ? item.superset_group_id === id : item.alternating_group_id === id,
    );
    result.push({
      type: "group",
      id,
      kind,
      sets: exercise.group_config?.sets ?? exercise.sets ?? null,
      title: exercise.group_config?.title ?? null,
      exercises: members,
    });
  }

  return result;
}

function presentationGroupColor(id: string) {
  const colors = ["var(--primary)", "var(--info)", "var(--success)", "var(--warning)", "var(--danger)"];
  const hash = Array.from(id).reduce((sum, character) => sum + character.charCodeAt(0), 0);
  return colors[hash % colors.length];
}

export function WorkoutPreviewDetail({
  sections,
  initiallyExpanded = true,
  activeScaleOverride,
  hideScaleChips = false,
}: Props) {
  const i18n = useUiTranslations();

  function formatTimerLabel(timerConfig: Record<string, unknown> | null | undefined): string | null {
    if (!timerConfig) return null;
    const type = timerConfig.type as string | undefined;
    if (!type || type === "untimed") return null;
    if (type === "amrap" && timerConfig.duration_seconds) return i18n("amrapValue0Minf963ab5", {value0: Math.round((timerConfig.duration_seconds as number) / 60)});
    if (type === "emom" && timerConfig.duration_seconds) return i18n("emomValue0Min517ea41", {value0: Math.round((timerConfig.duration_seconds as number) / 60)});
    if (type === "for_time") return i18n("forTimea8ed8eb");
    return semanticLabel(type, i18n);
  }

  const [expandedSections, setExpandedSections] = useState<Set<string>>(() => {
    if (!initiallyExpanded) return new Set();
    return new Set(sections.map((s, i) => s.id ?? String(i)));
  });
  const [sectionScales, setSectionScales] = useState<Record<string, string | null>>({});

  function toggleSection(key: string) {
    setExpandedSections((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }

  if (sections.length === 0) {
    return (
      <p className="text-sm" style={{ color: "var(--dim)" }}>
        {i18n("noExercisesConfigured0becaba")}
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {sections.map((section, i) => {
        const key = section.id ?? String(i);
        const expanded = expandedSections.has(key);
        const timerLabel = formatTimerLabel(section.timer_config);
        const scaleOptions = sectionScaleOptions(section);
        const activeScale = activeScaleOverride !== undefined ? activeScaleOverride : (sectionScales[key] ?? null);
        const baseColor = scaleLevelVar("base");
        const visibleExercises = section.exercises
          .map((exercise) => resolveExercise(exercise, activeScale))
          .filter((exercise): exercise is ResolvedExercise => Boolean(exercise));
        const exerciseCount = visibleExercises.filter((exercise) => exercise.item_type !== "header").length;
        const presentedExercises = presentExercises(visibleExercises);

        return (
          <div
            key={key}
            className="rounded-[1.2rem] overflow-hidden"
            style={{ border: "1px solid var(--border)" }}
          >
            <button
              aria-expanded={expanded}
              className="flex w-full items-center justify-between gap-3 px-4 py-3 text-start"
              style={{ background: "var(--panel)" }}
              onClick={() => toggleSection(key)}
              type="button"
            >
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {section.name}
                </span>
                {timerLabel ? (
                  <span
                    className="rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.18em]"
                    style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
                  >
                    {timerLabel}
                  </span>
                ) : null}
                {section.scoreable ? (
                  <span
                    className="rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.18em]"
                    style={{ background: "color-mix(in srgb, var(--info) 12%, transparent)", color: "var(--info)" }}
                  >
                    {i18n("scoredc6702fe")}
                  </span>
                ) : null}
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
                  {i18n("featureExerciseCount", { count: exerciseCount })}
                </span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>
                  {expanded ? "▲" : "▼"}
                </span>
              </div>
            </button>

            {scaleOptions.length > 0 && !hideScaleChips ? (
              <div
                className="flex flex-wrap gap-1.5 px-3 pb-2 pt-2"
                style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}
              >
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                  style={{
                    background: activeScale === null ? baseColor : "var(--card)",
                    color: activeScale === null ? "var(--bg)" : "var(--text-soft)",
                    border: activeScale === null ? `1px solid ${baseColor}` : "1px solid var(--border-strong)",
                  }}
                  onClick={(e) => { e.stopPropagation(); setSectionScales((current) => ({ ...current, [key]: null })); }}
                  type="button"
                >
                  {i18n("base077fe9c")}
                </button>
                {scaleOptions.map((scale, si) => {
                  const color = scaleLevelVar(scale.slug || scale.label || String(si));
                  const isActive = activeScale === scale.slug;
                  return (
                    <button
                      key={scale.slug}
                      className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                      style={{
                        background: isActive ? translucent(color, 18) : "var(--card)",
                        color: isActive ? color : "var(--text-soft)",
                        border: isActive ? `1px solid ${translucent(color, 55)}` : "1px solid var(--border-strong)",
                      }}
                      onClick={(e) => { e.stopPropagation(); setSectionScales((current) => ({ ...current, [key]: scale.slug })); }}
                      type="button"
                    >
                      {scale.label}
                    </button>
                  );
                })}
              </div>
            ) : null}

            {section.note ? (
              <div
                className="px-4 py-2 text-xs italic"
                style={{ background: "var(--panel)", borderTop: "1px solid var(--border)", color: "var(--muted)" }}
              >
                {section.note}
              </div>
            ) : null}

            {expanded ? (
              <div className="space-y-3 p-3" style={{ background: "var(--panel)" }}>
                {visibleExercises.length > 0 ? (
                  <div className="space-y-2">
                    {presentedExercises.map((item, ei) => {
                      if (item.type === "exercise") {
                        return <ul className="space-y-2" key={item.exercise.id ?? `${key}-${ei}`}><ExerciseRow exercise={item.exercise} /></ul>;
                      }

                      const color = presentationGroupColor(item.id);
                      const label = item.title || (item.kind === "superset" ? i18n("supersetLabel") : i18n("alternatingSetsLabel"));
                      const setLabel = item.sets ? ` · ${item.sets} ${i18n("setsd6c8220")}` : "";
                      return (
                        <section
                          aria-label={`${label}${setLabel}`}
                          className="rounded-[1rem] border p-3"
                          key={item.id}
                          role="group"
                          style={{ borderColor: `color-mix(in srgb, ${color} 45%, var(--border))` }}
                        >
                          <header className="mb-2 flex items-center gap-2 text-xs font-bold uppercase" style={{ color }}>
                            <span>{label}</span>
                            {item.sets ? <span>{item.sets} {i18n("setsd6c8220")}</span> : null}
                            <span className="h-px flex-1" style={{ background: color, opacity: 0.3 }} />
                          </header>
                          <ul className="space-y-2">
                            {item.exercises.map((exercise, index) => (
                              <ExerciseRow key={exercise.id ?? `${item.id}-${index}`} exercise={exercise} groupColor={color} />
                            ))}
                          </ul>
                        </section>
                      );
                    })}
                  </div>
                ) : (
                  <p
                    className="rounded-[1rem] px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--dim)" }}
                  >
                    {i18n("noExercisesForThisScale94e9906")}
                  </p>
                )}
              </div>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
