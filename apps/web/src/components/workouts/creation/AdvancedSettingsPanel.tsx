"use client";






import {useUiTranslations} from "@/i18n/ui";
import { semanticLabel } from "@/i18n/presentation";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftExercise, DraftSection, LoadMode } from "@/types/workout";

import { NumberStepper } from "./NumberStepper";
import { TimeInput } from "./TimeInput";
import { UnitCycler } from "./UnitCycler";
import { IntegerInput } from "@/components/integer-input";

type SettingKey = keyof DraftExercise["advanced"];

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  sectionOptions?: Array<{ id: string; name: string }>;
};

export function AdvancedSettingsPanel({ exercise, section, sectionOptions = [] }: Props) {
  const i18n = useUiTranslations();
  const SETTINGS: Array<{
    key: SettingKey;
    label: string;
    unit: string;
    inputType: "number" | "text";
  }> = [
    { key: "hrZone", label: i18n("heartRateZonec0085b9"), unit: "zone", inputType: "number" },
    { key: "tempo", label: i18n("tempo899658e"), unit: "", inputType: "text" },
    { key: "restSeconds", label: i18n("restBetweenSets39fb31b"), unit: "secs", inputType: "number" },
    { key: "clusterRestSeconds", label: i18n("clusterSetsIntraRestfc8fbe2"), unit: "secs", inputType: "number" },
    { key: "restPauseSeconds", label: i18n("restPause62e1845"), unit: "secs", inputType: "number" },
    { key: "pacing", label: i18n("pacing43ab6ce"), unit: "per_kilometre", inputType: "number" },
  ];
  const { toggleAdvancedPanel, toggleAdvancedSetting, updateAdvancedValue, updateExercise, deleteExercise, moveExercise } =
    useWorkoutCreationStore();
  const loadModes: LoadMode[] = ["absolute", "pct_1rm", "bw"];
  const loadLabels: Record<LoadMode, string> = { absolute: i18n("kilogramsUnit"), pct_1rm: i18n("percentOneRepMaxUnit"), bw: i18n("bw4d64743") };
  const progression = exercise.loadProgression;
  const update = (patch: Partial<DraftExercise>) => updateExercise(section.localId, exercise.localId, patch);

  return (
    <div className="border-t px-4 pb-4" style={{ borderColor: "var(--accent)" }}>
      <div className="flex items-center justify-between py-2">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          {i18n("advancedSettingsc8fef35")}
        </span>
        <button
          onClick={() => toggleAdvancedPanel(section.localId, exercise.localId)}
          className="text-xs"
          style={{ color: "var(--muted)" }}
        >
          {i18n("closebbfa773")}
        </button>
      </div>

      <div className="flex flex-col gap-1">
        {SETTINGS.filter(({ key }) => key !== "clusterRestSeconds" || section.format === "cluster").map(({ key, label, unit, inputType }) => {
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
                  className="absolute top-0.5 h-3 w-3 rounded-full bg-[var(--panel)] transition-transform"
                  style={{ transform: setting.enabled ? "translateX(18px)" : "translateX(2px)" }}
                />
              </button>

              <span className="flex-1 text-sm" style={{ color: setting.enabled ? "var(--text)" : "var(--muted)" }}>
                {label}
              </span>

              {setting.enabled ? (
                <div className="shrink-0 flex items-center gap-2">
                  {unit === "secs" ? (
                    <TimeInput
                      value={typeof setting.value === "number" ? setting.value : null}
                      onChange={(secs) =>
                        updateAdvancedValue(section.localId, exercise.localId, key, secs ?? 0)
                      }
                    />
                  ) : (
                    <>
                      {inputType === "number" ? <IntegerInput value={typeof setting.value === "number" ? setting.value : null} emptyValue={0} onValueChange={(value) => updateAdvancedValue(section.localId, exercise.localId, key, value ?? 0)} className="w-16 rounded-lg px-2 py-1 text-end text-sm outline-none" style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }} /> : <input type="text" value={String(setting.value)} onChange={(event) => updateAdvancedValue(section.localId, exercise.localId, key, event.target.value)} className="w-16 rounded-lg px-2 py-1 text-end text-sm outline-none" style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }} />}
                      {unit ? (
                        <span className="text-sm" style={{ color: "var(--muted)" }}>
                          {semanticLabel(unit, i18n)}
                        </span>
                      ) : null}
                    </>
                  )}
                </div>
              ) : null}
            </div>
          );
        })}
      </div>

      {exercise.loadMode !== "bw" ? (
        <section className="mt-4 border-t pt-3" style={{ borderColor: "var(--border)" }}>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-bold uppercase" style={{ color: "var(--muted)" }}>{i18n("loadProgression1c3f8ed")}</span>
            {!progression ? (
              <button type="button" className="rounded-md px-3 py-1.5 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} onClick={() => update({ loadProgression: { mode: "linear", direction: "increase", startValue: exercise.loadValue ?? 40, startMode: exercise.loadMode, stepValue: 10, perSetValues: [] }, loadValue: null })}>
                {i18n("setProgressiveLoadAcrossSetsb3a6402")}
              </button>
            ) : (
              <>
                <button type="button" className="rounded-md px-2 py-1 text-xs" style={{ background: "var(--panel-muted)" }} onClick={() => update({ loadProgression: { ...progression, mode: progression.mode === "linear" ? "per_set" : "linear" } })}>
                  {progression.mode === "linear" ? i18n("linearaf502f2") : i18n("perSet1e0dfe5")}
                </button>
                <button type="button" className="rounded-md px-2 py-1 text-xs" style={{ background: "var(--panel-muted)" }} onClick={() => update({ loadProgression: { ...progression, direction: progression.direction === "increase" ? "decrease" : "increase" } })}>
                  {progression.direction === "increase" ? i18n("progressiveLoadIncrease") : i18n("progressiveLoadDecrease")}
                </button>
                <NumberStepper min={0} value={progression.startValue} onChange={(startValue) => update({ loadProgression: { ...progression, startValue } })} />
                <UnitCycler labels={loadLabels} options={loadModes} value={progression.startMode} onChange={(startMode) => update({ loadProgression: { ...progression, startMode } })} />
                <span style={{ color: "var(--muted)" }}>{progression.direction === "increase" ? "+" : "-"}</span>
                <NumberStepper min={0} value={progression.stepValue} onChange={(stepValue) => update({ loadProgression: { ...progression, stepValue } })} />
                <button type="button" className="ms-auto text-xs" style={{ color: "var(--danger)" }} onClick={() => update({ loadProgression: null })}>{i18n("removee963907")}</button>
                {progression.mode === "per_set" ? <div className="flex w-full flex-wrap gap-2 pt-2">{Array.from({ length: exercise.sets }, (_, index) => <label className="flex items-center gap-1 text-xs" key={index} style={{ color: "var(--muted)" }}>{i18n("setNumberLabel", { number: index + 1 })}<NumberStepper min={0} value={progression.perSetValues[index] ?? progression.startValue} onChange={(value) => { const perSetValues = [...progression.perSetValues]; while (perSetValues.length <= index) perSetValues.push(progression.startValue); perSetValues[index] = value; update({ loadProgression: { ...progression, perSetValues } }); }} /></label>)}</div> : null}
              </>
            )}
          </div>
        </section>
      ) : null}

      {sectionOptions.length > 0 ? (
        <div className="mt-4 flex items-center gap-3">
          <span className="text-sm" style={{ color: "var(--muted)" }}>
            {i18n("moveToSection98d183e")}
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
            <option value="">{i18n("select8598222")}</option>
            {sectionOptions
              .filter((option) => option.id !== section.localId)
              .map((option) => (
                <option key={option.id} value={option.id}>
                  {option.name || i18n("unnamedSection109fa70")}
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
        {i18n("removeExercise4c52294")}
      </button>
    </div>
  );
}
