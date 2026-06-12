"use client";

import { useWorkoutCreationStore } from "@/stores/workout-creation";
import {
  AUTO_SCORE_MAP,
  EMOM_SCORING_MODE_DESCRIPTIONS,
  EMOM_SCORING_MODE_LABELS,
  type DraftSection,
  type EmomScoringMode,
  type ScoreType,
} from "@/types/workout";

import { FormatContextualFields } from "./FormatContextualFields";
import { FormatDropdown } from "./FormatDropdown";
import { TimeInput } from "./TimeInput";

const SCORE_TYPES: ScoreType[] = ["time", "reps", "weight", "rounds", "rounds+reps", "kcal", "hr_drop", "load"];

type Props = {
  section: DraftSection;
};

export function SectionConfig({ section }: Props) {
  const { updateSection, setFormat, setFormatParams, deleteSection, setEmomScoringMode, setEmomAmrapScoringStyle } = useWorkoutCreationStore();

  const autoScore = AUTO_SCORE_MAP[section.format];
  const isEmomFormat = section.format === "emom" || section.format === "complex_emom";
  // For EMOM formats, scoring mode picker replaces the generic score type select
  const showScorePicker = section.scoreable && !autoScore && !isEmomFormat;
  const showEmomScoringPicker = section.scoreable && isEmomFormat;
  const showAmrapStyle =
    showEmomScoringPicker &&
    section.format === "complex_emom" &&
    section.emomScoringMode === "amrap";
  const showMaxWindows = showEmomScoringPicker && section.emomScoringMode === "to_failure";

  return (
    <div className="flex flex-col gap-4 p-4">
      <div className="flex items-center justify-between">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Section Config
        </span>
        <button onClick={() => deleteSection(section.localId)} className="text-xs" style={{ color: "var(--red)" }}>
          Delete
        </button>
      </div>

      <div>
        <label className="mb-1 block text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Name
        </label>
        <input
          type="text"
          value={section.name}
          onChange={(event) => updateSection(section.localId, { name: event.target.value })}
          placeholder="e.g. Main Set"
          className="w-full rounded-xl px-3 py-2 text-sm outline-none"
          style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }}
        />
      </div>

      <div>
        <label className="mb-1 block text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Format
        </label>
        <FormatDropdown value={section.format} onChange={(format) => setFormat(section.localId, format)} />
        <FormatContextualFields
          format={section.format}
          params={section.formatParams}
          onChange={(params) => setFormatParams(section.localId, params)}
        />
        {section.format === "complex_emom" && (() => {
          const totalDuration = (section.formatParams.duration_seconds as number) || 0;
          const minuteCount = (section.formatParams.minute_count as number) || 0;
          const maxAssigned = section.exercises.reduce<number>((acc, e) => {
            return e.intervalAssignment !== null ? Math.max(acc, e.intervalAssignment) : acc;
          }, 0);
          const totalMinutes = Math.max(minuteCount, maxAssigned);

          let cycleDuration = 0;
          for (let min = 1; min <= totalMinutes; min++) {
            cycleDuration += ((section.formatParams[`interval_seconds_${min}`] as number)
              ?? (section.formatParams.interval_seconds as number)
              ?? 60);
          }

          const rounds = totalMinutes > 0 && cycleDuration > 0 && totalDuration > 0
            ? Math.floor(totalDuration / cycleDuration)
            : null;
          const remainder = rounds !== null ? totalDuration % cycleDuration : 0;
          const suggestedDuration = rounds !== null && rounds > 0 ? rounds * cycleDuration : cycleDuration;

          function toMMSS(secs: number): string {
            const m = Math.floor(secs / 60);
            const s = secs % 60;
            return m > 0 ? (s > 0 ? `${m}:${String(s).padStart(2, "0")}` : `${m}min`) : `${secs}s`;
          }

          return (
            <div className="mt-3 flex flex-col gap-3">
              <div>
                <label className="mb-2 block text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
                  Minutes in Cycle
                </label>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() =>
                      setFormatParams(section.localId, {
                        ...section.formatParams,
                        minute_count: Math.max(0, minuteCount - 1),
                      })
                    }
                    className="rounded-lg px-2.5 py-1 text-sm font-bold"
                    style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--muted)" }}
                  >
                    −
                  </button>
                  <span className="min-w-[2rem] text-center text-sm font-bold" style={{ color: "var(--text)" }}>
                    {totalMinutes || "—"}
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      setFormatParams(section.localId, {
                        ...section.formatParams,
                        minute_count: minuteCount + 1,
                      })
                    }
                    className="rounded-lg px-2.5 py-1 text-sm font-bold"
                    style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--muted)" }}
                  >
                    +
                  </button>
                  {rounds !== null ? (
                    <span className="ml-1 text-xs" style={{ color: "var(--dim)" }}>
                      → {rounds} round{rounds !== 1 ? "s" : ""}
                    </span>
                  ) : null}
                </div>
              </div>

              {totalMinutes > 0 ? (
                <div>
                  <label className="mb-2 block text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
                    Per-Minute Duration
                  </label>
                  <div className="flex flex-col gap-2">
                    {Array.from({ length: totalMinutes }, (_, i) => i + 1).map((min) => (
                      <div key={min} className="flex items-center justify-between gap-2">
                        <span className="text-xs" style={{ color: "var(--muted)" }}>Min {min}</span>
                        <TimeInput
                          value={((section.formatParams[`interval_seconds_${min}`] as number)
                            ?? (section.formatParams.interval_seconds as number)
                            ?? 60)}
                          onChange={(secs) =>
                            setFormatParams(section.localId, {
                              ...section.formatParams,
                              [`interval_seconds_${min}`]: secs,
                            })
                          }
                        />
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}

              {totalDuration > 0 && totalMinutes > 0 && remainder !== 0 && rounds !== null ? (
                <div
                  className="flex items-center justify-between gap-2 rounded-xl px-3 py-2 text-xs"
                  style={{
                    background: "color-mix(in srgb, #f59e0b 12%, transparent)",
                    border: "1px solid color-mix(in srgb, #f59e0b 35%, transparent)",
                    color: "#f59e0b",
                  }}
                >
                  <span>
                    {remainder}s leftover — {toMMSS(suggestedDuration)} fits exactly
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      setFormatParams(section.localId, {
                        ...section.formatParams,
                        duration_seconds: suggestedDuration,
                      })
                    }
                    className="shrink-0 rounded-lg px-2 py-0.5 font-bold"
                    style={{
                      background: "color-mix(in srgb, #f59e0b 20%, transparent)",
                      border: "1px solid #f59e0b",
                    }}
                  >
                    Fix
                  </button>
                </div>
              ) : null}
            </div>
          );
        })()}
      </div>

      <div>
        <label className="mb-1 block text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Rest After Section
          <span className="ml-1 font-normal italic normal-case" style={{ color: "var(--dim)" }}>optional</span>
        </label>
        <TimeInput
          value={section.restAfterSeconds}
          onChange={(secs) => updateSection(section.localId, { restAfterSeconds: secs })}
        />
      </div>

      {section.format !== "rest" ? (
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => updateSection(section.localId, { scoreable: !section.scoreable })}
            className="relative h-5 w-10 rounded-full transition-colors"
            style={{ background: section.scoreable ? "var(--accent)" : "var(--dim)" }}
          >
            <span
              className="absolute top-0.5 h-4 w-4 rounded-full bg-white transition-transform"
              style={{ transform: section.scoreable ? "translateX(22px)" : "translateX(2px)" }}
            />
          </button>
          <span className="text-sm" style={{ color: "var(--text)" }}>
            Scoreable
          </span>
        </div>
      ) : null}

      {showEmomScoringPicker ? (
        <div>
          <label
            className="mb-2 block text-xs font-bold uppercase tracking-widest"
            style={{ color: "var(--muted)" }}
          >
            Scoring Mode
          </label>
          <div className="flex flex-col gap-2">
            {(["for_time", "for_quality", "amrap", "to_failure"] as EmomScoringMode[]).map((mode) => (
              <button
                key={mode}
                type="button"
                onClick={() => setEmomScoringMode(section.localId, mode)}
                className="flex flex-col gap-0.5 rounded-xl px-3 py-2 text-left transition-colors"
                style={
                  section.emomScoringMode === mode
                    ? {
                        background: "color-mix(in srgb, var(--accent) 15%, transparent)",
                        border: "1px solid var(--accent)",
                        color: "var(--text)",
                      }
                    : {
                        background: "var(--bg)",
                        border: "1px solid var(--dim)",
                        color: "var(--muted)",
                      }
                }
              >
                <span className="text-xs font-bold">{EMOM_SCORING_MODE_LABELS[mode]}</span>
                <span className="text-xs leading-tight" style={{ color: "var(--dim)" }}>
                  {EMOM_SCORING_MODE_DESCRIPTIONS[mode]}
                </span>
              </button>
            ))}
          </div>
        </div>
      ) : null}

      {showAmrapStyle ? (
        <div>
          <label
            className="mb-2 block text-xs font-bold uppercase tracking-widest"
            style={{ color: "var(--muted)" }}
          >
            AMRAP Scoring Style
          </label>
          <div className="flex gap-2">
            {(["grand_total", "lowest_window"] as const).map((style) => (
              <button
                key={style}
                type="button"
                onClick={() => setEmomAmrapScoringStyle(section.localId, style)}
                className="flex-1 rounded-xl px-3 py-2 text-xs font-bold transition-colors"
                style={
                  section.emomAmrapScoringStyle === style ||
                  (section.emomAmrapScoringStyle === null && style === "grand_total")
                    ? {
                        background: "color-mix(in srgb, var(--accent) 15%, transparent)",
                        border: "1px solid var(--accent)",
                        color: "var(--text)",
                      }
                    : {
                        background: "var(--bg)",
                        border: "1px solid var(--dim)",
                        color: "var(--muted)",
                      }
                }
              >
                {style === "grand_total" ? "Grand Total" : "Lowest Window"}
              </button>
            ))}
          </div>
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
            {section.emomAmrapScoringStyle === "lowest_window"
              ? "Score = your worst window. Punishes inconsistent pacing."
              : "Score = sum of all reps across all windows."}
          </p>
        </div>
      ) : null}

      {showMaxWindows ? (
        <div className="flex items-center justify-between gap-2">
          <label
            className="shrink-0 text-xs font-bold uppercase tracking-widest"
            style={{ color: "var(--muted)" }}
          >
            Max Windows
          </label>
          <input
            type="number"
            min={1}
            max={200}
            value={(section.formatParams.max_windows as number) ?? 100}
            onChange={(event) =>
              setFormatParams(section.localId, {
                ...section.formatParams,
                max_windows: Math.max(1, Number(event.target.value) || 1),
              })
            }
            className="w-20 rounded-lg px-2 py-1 text-right text-sm outline-none"
            style={{
              background: "var(--bg)",
              border: "1px solid var(--dim)",
              color: "var(--text)",
            }}
          />
        </div>
      ) : null}

      {showScorePicker ? (
        <div>
          <label className="mb-1 block text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
            Score Type
          </label>
          <select
            value={section.scoreType ?? ""}
            onChange={(event) => updateSection(section.localId, { scoreType: event.target.value as ScoreType })}
            className="w-full rounded-xl px-3 py-2 text-sm outline-none"
            style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }}
          >
            <option value="">Select score type</option>
            {SCORE_TYPES.map((scoreType) => (
              <option key={scoreType} value={scoreType}>
                {scoreType}
              </option>
            ))}
          </select>
        </div>
      ) : null}
    </div>
  );
}
