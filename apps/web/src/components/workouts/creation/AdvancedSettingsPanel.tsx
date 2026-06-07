"use client";

import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftExercise, DraftSection } from "@/types/workout";

type SettingKey = keyof DraftExercise["advanced"];

const SETTINGS: Array<{
  key: SettingKey;
  label: string;
  unit: string;
  inputType: "number" | "text";
}> = [
  { key: "hrZone", label: "Heart Rate Zone", unit: "Zone", inputType: "number" },
  { key: "tempo", label: "Tempo", unit: "", inputType: "text" },
  { key: "restSeconds", label: "Rest Between Sets", unit: "secs", inputType: "number" },
  { key: "clusterRestSeconds", label: "Cluster Sets Intra-Rest", unit: "secs", inputType: "number" },
  { key: "restPauseSeconds", label: "Rest-Pause", unit: "secs", inputType: "number" },
  { key: "pacing", label: "Pacing", unit: "/km", inputType: "number" },
];

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  sectionOptions?: Array<{ id: string; name: string }>;
};

export function AdvancedSettingsPanel({ exercise, section, sectionOptions = [] }: Props) {
  const { toggleAdvancedPanel, toggleAdvancedSetting, updateAdvancedValue, deleteExercise, moveExercise } =
    useWorkoutCreationStore();

  return (
    <div className="border-t px-4 pb-4" style={{ borderColor: "var(--accent)" }}>
      <div className="flex items-center justify-between py-2">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Advanced Settings
        </span>
        <button
          onClick={() => toggleAdvancedPanel(section.localId, exercise.localId)}
          className="text-xs"
          style={{ color: "var(--muted)" }}
        >
          Close
        </button>
      </div>

      <div className="flex flex-col gap-1">
        {SETTINGS.map(({ key, label, unit, inputType }) => {
          const setting = exercise.advanced[key];

          return (
            <div key={key} className="flex items-center gap-3 py-1.5">
              <button
                type="button"
                onClick={() => toggleAdvancedSetting(section.localId, exercise.localId, key)}
                className="relative h-4 w-8 shrink-0 rounded-full transition-colors"
                style={{ background: setting.enabled ? "var(--accent)" : "var(--dim)" }}
              >
                <span
                  className="absolute top-0.5 h-3 w-3 rounded-full bg-white transition-transform"
                  style={{ transform: setting.enabled ? "translateX(18px)" : "translateX(2px)" }}
                />
              </button>

              <span className="flex-1 text-sm" style={{ color: setting.enabled ? "var(--text)" : "var(--muted)" }}>
                {label}
              </span>

              {setting.enabled ? (
                <div className="shrink-0 flex items-center gap-2">
                  <input
                    type={inputType}
                    value={String(setting.value)}
                    onChange={(event) =>
                      updateAdvancedValue(
                        section.localId,
                        exercise.localId,
                        key,
                        inputType === "number" ? Number.parseInt(event.target.value, 10) || 0 : event.target.value,
                      )
                    }
                    className="w-16 rounded-lg px-2 py-1 text-right text-sm outline-none"
                    style={{
                      background: "var(--bg)",
                      border: "1px solid var(--dim)",
                      color: "var(--text)",
                    }}
                  />
                  {unit ? (
                    <span className="text-sm" style={{ color: "var(--muted)" }}>
                      {unit}
                    </span>
                  ) : null}
                </div>
              ) : null}
            </div>
          );
        })}
      </div>

      {sectionOptions.length > 0 ? (
        <div className="mt-4 flex items-center gap-3">
          <span className="text-sm" style={{ color: "var(--muted)" }}>
            Move to section
          </span>
          <select
            defaultValue=""
            onChange={(event) => {
              const nextSectionId = event.target.value;
              if (!nextSectionId) return;
              moveExercise(exercise.localId, section.localId, nextSectionId);
              event.target.value = "";
            }}
            className="rounded-xl px-3 py-2 text-sm outline-none"
            style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }}
          >
            <option value="">Select</option>
            {sectionOptions
              .filter((option) => option.id !== section.localId)
              .map((option) => (
                <option key={option.id} value={option.id}>
                  {option.name || "Unnamed section"}
                </option>
              ))}
          </select>
        </div>
      ) : null}

      <button
        onClick={() => deleteExercise(section.localId, exercise.localId)}
        className="mt-4 text-xs font-semibold"
        style={{ color: "var(--red)" }}
      >
        Remove exercise
      </button>
    </div>
  );
}
