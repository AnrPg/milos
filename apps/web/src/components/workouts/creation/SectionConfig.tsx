"use client";

import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { AUTO_SCORE_MAP, type DraftSection, type ScoreType } from "@/types/workout";

import { FormatContextualFields } from "./FormatContextualFields";
import { FormatDropdown } from "./FormatDropdown";

const SCORE_TYPES: ScoreType[] = ["time", "reps", "weight", "rounds", "rounds+reps", "kcal", "hr_drop", "load"];

type Props = {
  section: DraftSection;
};

export function SectionConfig({ section }: Props) {
  const { updateSection, setFormat, setFormatParams, deleteSection } = useWorkoutCreationStore();

  const autoScore = AUTO_SCORE_MAP[section.format];
  const showScorePicker = section.scoreable && !autoScore;

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
