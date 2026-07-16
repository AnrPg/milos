"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";

import type { ScaleLevel } from "@/api/workouts";
import { FORMAT_EXERCISE_CONTEXT, FORMAT_LABELS, getFormatInstruction, type DraftExercise, type DraftSection, type LoadMode, type LoadProgression, type PrescriptionUnit } from "@/types/workout";

import { FormatTooltip } from "./FormatTooltip";

type Props = {
  section: DraftSection;
  activeScale: string | null;
  scaleLevels: ScaleLevel[];
};

type ResolvedExercise = {
  name: string;
  sets: number;
  prescriptionValue: number;
  prescriptionUnit: PrescriptionUnit;
  loadValue: number | null;
  loadMode: LoadMode;
  loadProgression: LoadProgression | null;
  clustersPerSet: number | null;
  excluded: boolean;
  varied: boolean;
};

function resolveExercise(
  exercise: DraftExercise,
  activeScale: string | null,
): ResolvedExercise {
  if (!activeScale) {
    return {
      name: exercise.name,
      sets: exercise.sets,
      prescriptionValue: exercise.prescriptionValue,
      prescriptionUnit: exercise.prescriptionUnit,
      loadValue: exercise.loadValue,
      loadMode: exercise.loadMode,
      loadProgression: exercise.loadProgression,
      clustersPerSet: exercise.clustersPerSet,
      excluded: false,
      varied: false,
    };
  }

  const variation = exercise.variations.find((item) => item.scaleLevelSlug === activeScale);

  if (!variation) {
    return {
      name: exercise.name,
      sets: exercise.sets,
      prescriptionValue: exercise.prescriptionValue,
      prescriptionUnit: exercise.prescriptionUnit,
      loadValue: exercise.loadValue,
      loadMode: exercise.loadMode,
      loadProgression: exercise.loadProgression,
      clustersPerSet: exercise.clustersPerSet,
      excluded: false,
      varied: false,
    };
  }

  if (variation.excluded) {
    return {
      name: exercise.name,
      sets: exercise.sets,
      prescriptionValue: exercise.prescriptionValue,
      prescriptionUnit: exercise.prescriptionUnit,
      loadValue: exercise.loadValue,
      loadMode: exercise.loadMode,
      loadProgression: exercise.loadProgression,
      clustersPerSet: exercise.clustersPerSet,
      excluded: true,
      varied: true,
    };
  }

  return {
    name: variation.exerciseNameOverride ?? exercise.name,
    sets: variation.sets ?? exercise.sets,
    prescriptionValue: variation.prescriptionValue ?? exercise.prescriptionValue,
    prescriptionUnit: variation.prescriptionUnit ?? exercise.prescriptionUnit,
    loadValue: variation.loadValue ?? exercise.loadValue,
    loadMode: variation.loadMode ?? exercise.loadMode,
    loadProgression: exercise.loadProgression,
    clustersPerSet: exercise.clustersPerSet,
    excluded: false,
    varied: true,
  };
}

export function PreviewSection({ section, activeScale, scaleLevels }: Props) {
  const i18n = useUiTranslations();
  const [collapsed, setCollapsed] = useState(false);
  const isEmpty = section.exercises.length === 0;

  const params = section.formatParams;
  const formatInstruction = getFormatInstruction(section.format, params);

  return (
    <div className="mb-3">
      <button onClick={() => setCollapsed((current) => !current)} className="w-full py-2 text-left">
        <div className="flex items-center justify-between gap-2">
          <div>
            <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
              {section.name || i18n("unnamedSection109fa70")}
            </span>
            <FormatTooltip format={section.format}>
              <span className="ml-2 text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
                {FORMAT_LABELS[section.format]}
              </span>
            </FormatTooltip>
          </div>
          <div className="flex items-center gap-2">
            {isEmpty ? (
              <span className="text-xs" style={{ color: "var(--amber)" }}>
                {i18n("noExercises4afd141")}
              </span>
            ) : null}
            <span className="text-xs" style={{ color: "var(--muted)" }}>
              {collapsed ? ">" : "v"}
            </span>
          </div>
        </div>
        {formatInstruction ? (
          <div className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
            {formatInstruction}
          </div>
        ) : null}
      </button>

      {!collapsed ? (
        <div className="flex flex-col gap-1 pl-2">
          {section.exercises.map((exercise) => {
            const resolved = resolveExercise(exercise, activeScale);
            const scaleLevel = activeScale ? scaleLevels.find((item) => item.slug === activeScale) : null;

            if (resolved.excluded) {
              return (
                <div
                  key={exercise.localId}
                  className="py-1 text-xs"
                  style={{ color: "var(--dim)", textDecoration: "line-through" }}
                >
                  {exercise.name}
                  {scaleLevel ? "(" + (scaleLevel.label) + ")" : ""}
                </div>
              );
            }

            const adv = exercise.advanced;
            const advancedLines: string[] = [];
            if (adv.tempo.enabled) advancedLines.push(i18n("tempo899658e") + (adv.tempo.value));
            if (adv.hrZone.enabled) advancedLines.push(i18n("hrZone227bd0b") + (adv.hrZone.value));
            if (adv.restSeconds.enabled) advancedLines.push(i18n("restb79e5f4") + (adv.restSeconds.value) + "s");
            if (adv.clusterRestSeconds.enabled) advancedLines.push(i18n("clusterRest7330841") + (adv.clusterRestSeconds.value) + "s");
            if (adv.restPauseSeconds.enabled) advancedLines.push(i18n("restPause0acc186") + (adv.restPauseSeconds.value) + "s");
            if (adv.pacing.enabled) advancedLines.push(i18n("pace7a9a622") + (adv.pacing.value) + "/km");

            const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
            const step = exercise.prescriptionStep ?? 1;
            let loadStr = "";
            if (resolved.loadMode === "bw") {
              loadStr = i18n("bw2c0410b");
            } else if (resolved.loadProgression) {
              const prog = resolved.loadProgression;
              const unit = prog.startMode === "pct_1rm" ? "%RM" : "kg";
              if (prog.mode === "linear") {
                const end = prog.startValue + prog.stepValue * (resolved.sets - 1);
                loadStr = "· " + (prog.startValue) + "→" + (end) + (unit) + " (+" + (prog.stepValue) + (unit) + "/set)";
              } else {
                const vals = Array.from({ length: resolved.sets }, (_, i) =>
                  prog.perSetValues[i] ?? prog.startValue,
                );
                loadStr = "· " + (vals.join("/")) + (unit);
              }
            } else if (resolved.loadValue != null) {
              loadStr = "· " + (resolved.loadValue) + " " + (resolved.loadMode === "pct_1rm" ? "%RM" : "kg");
            }

            let prescriptionText = "";
            if (!ctx.showPrescription) {
              if (section.format === "train_to_exhaustion") {
                prescriptionText = (resolved.sets) + i18n("setsToFailure4e16bb2");
              }
            } else if (ctx.ladderPrescription) {
              if (section.format === "pyramid") {
                prescriptionText = "peak " + (resolved.prescriptionValue) + " " + (resolved.prescriptionUnit) + ", ±" + (step) + "/round";
              } else {
                const dir = section.format === "ladder_descending" ? "−" : "+";
                prescriptionText = "start " + (resolved.prescriptionValue) + " " + (resolved.prescriptionUnit) + ", " + (dir) + (step) + "/round";
              }
            } else if (ctx.prescriptionHint) {
              prescriptionText = (resolved.prescriptionUnit) + " — " + (ctx.prescriptionHint);
            } else if (section.format === "cluster" && resolved.clustersPerSet) {
              prescriptionText = (resolved.sets) + " × " + (resolved.clustersPerSet) + i18n("clusters65add00") + (resolved.prescriptionValue) + " " + (resolved.prescriptionUnit);
            } else if (ctx.showSets) {
              const suffix = ctx.prescriptionSuffix ? "(" + (ctx.prescriptionSuffix) + ")" : "";
              prescriptionText = (resolved.sets) + " × " + (resolved.prescriptionValue) + " " + (resolved.prescriptionUnit) + (suffix);
            } else {
              const suffix = ctx.prescriptionSuffix ? "(" + (ctx.prescriptionSuffix) + ")" : "";
              prescriptionText = (resolved.prescriptionValue) + " " + (resolved.prescriptionUnit) + (suffix);
            }

            let prefixBadge: string | null = null;
            if (section.format === "even_odd" && exercise.intervalAssignment !== null) {
              prefixBadge = exercise.intervalAssignment === 1 ? i18n("odd710756a") : i18n("even70ca748");
            } else if (section.format === "complex_emom" && exercise.intervalAssignment !== null) {
              prefixBadge = i18n("min7eb0cee") + (exercise.intervalAssignment);
            }

            return (
              <div key={exercise.localId} className="py-1 text-xs">
                <div className="flex flex-wrap items-baseline gap-1.5">
                  {prefixBadge ? (
                    <span
                      className="rounded px-1.5 py-0.5 text-xs font-bold"
                      style={{
                        background: "color-mix(in srgb, var(--accent) 20%, transparent)",
                        color: "var(--accent)",
                      }}
                    >
                      {prefixBadge}
                    </span>
                  ) : null}
                  <span
                    className="font-semibold"
                    style={{ color: resolved.varied ? "var(--lime)" : "var(--text)" }}
                  >
                    {resolved.name || "—"}
                  </span>
                  {prescriptionText ? (
                    <span style={{ color: "var(--muted)" }}>
                      {prescriptionText}
                      {loadStr}
                    </span>
                  ) : null}
                  {!resolved.varied && activeScale ? (
                    <span className="italic" style={{ color: "var(--dim)" }}>
                      {i18n("base5ee057c")}
                    </span>
                  ) : null}
                </div>
                {advancedLines.length > 0 ? (
                  <div className="mt-0.5 pl-2" style={{ color: "var(--dim)" }}>
                    {advancedLines.join(" · ")}
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      ) : null}

      {section.restAfterSeconds ? (
        <div
          className="mt-1 flex items-center gap-2 py-1 text-xs"
          style={{ color: "var(--dim)" }}
        >
          <div className="h-px flex-1" style={{ background: "var(--dim)", opacity: 0.4 }} />
          <span>{i18n("restb79e5f4")} {section.restAfterSeconds >= 60
            ? (Math.round(section.restAfterSeconds / 60)) + "min"
            : (section.restAfterSeconds) + "s"}
          </span>
          <div className="h-px flex-1" style={{ background: "var(--dim)", opacity: 0.4 }} />
        </div>
      ) : null}
    </div>
  );
}
