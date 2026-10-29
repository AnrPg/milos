"use client";

import { useTranslations } from "next-intl";
import { useMemo, useState, type CSSProperties } from "react";

import { Combobox } from "@/components/ui/Combobox";
import { useUiTranslations } from "@/i18n/ui";
import { cellAttributes, rowKey } from "@/lib/structured-wod/grid";
import { shortcutLabel } from "@/lib/structured-wod/keymap";
import {
  formatLoad,
  formatPrescription,
  parseCount,
  parseLoad,
  parsePrescription,
  type Load,
  type Prescription,
} from "@/lib/structured-wod/quantity";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { concreteSetPrescriptions, FORMAT_EXERCISE_CONTEXT, type DraftExercise, type DraftSection } from "@/types/workout";

import { AdvancedSettingsPanel } from "../creation/AdvancedSettingsPanel";
import { VariationsPanel } from "../creation/VariationsPanel";
import { suggestExercises, useStructuredEditor } from "./editor-context";
import { QuantityField } from "./QuantityField";
import { RowMenu } from "./RowMenu";

export const cellClass = "min-w-0 rounded-lg border px-2 py-1.5 text-sm outline-none focus:border-[var(--primary)]";
export const cellStyle: CSSProperties = { background: "var(--card)", borderColor: "var(--border)", color: "var(--text)" };

type Props = {
  section: DraftSection;
  exercise: DraftExercise;
  /** Position among the section's rows (for the screen reader's row name). */
  index: number;
  /** The colour of the superset or alternating group the row belongs to. */
  groupColor: string | null;
  /** First row of its group: shows the group's name above it. */
  groupStart: "superset" | "alternating" | null;
  usedNames: string[];
  onCommand: (command: "newRow" | "delete" | "moveUp" | "moveDown" | "duplicate" | "superset" | "details" | "note", exerciseId: string) => void;
};

/**
 * ADR-270: one exercise as a row of text fields: interval · name · sets ·
 * reps/time/calories · load · details. The row's details (set by set, scaled
 * versions, rest, tempo, note) open under it with Alt+O.
 */
export function ExerciseRow({ section, exercise, index, groupColor, groupStart, usedNames, onCommand }: Props) {
  const t = useTranslations("StructuredWod");
  const i18n = useUiTranslations();
  const { mac, exerciseCatalog, bodyweightLabel, openDetails, openNotes } = useStructuredEditor();
  const updateExercise = useWorkoutCreationStore((state) => state.updateExercise);
  const [nameQuery, setNameQuery] = useState<string | null>(null);
  const key = rowKey({ kind: "exercise", sectionId: section.localId, exerciseId: exercise.localId });
  const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
  const detailsOpen = openDetails.has(key);
  const noteOpen = openNotes.has(key) || Boolean(exercise.note);
  const heading = exercise.itemType === "header";
  const grouped = Boolean(exercise.supersetGroupId ?? exercise.alternatingGroupId);

  const update = (patch: Partial<DraftExercise>) => updateExercise(section.localId, exercise.localId, patch);
  const suggestions = useMemo(
    () => (heading || nameQuery === null ? [] : suggestExercises(nameQuery, exerciseCatalog, usedNames)),
    [exerciseCatalog, heading, nameQuery, usedNames],
  );

  const prescription: Prescription | null =
    exercise.prescriptionValue > 0 ? { value: exercise.prescriptionValue, unit: exercise.prescriptionUnit } : null;
  const load: Load | null = exercise.loadMode === "bw" ? { mode: "bw", value: null } : exercise.loadValue ? { mode: exercise.loadMode, value: exercise.loadValue } : null;

  // Sets of a grouped row are the group's: changing one changes them all.
  function setSets(sets: number) {
    const groupId = exercise.supersetGroupId ?? exercise.alternatingGroupId;
    const members = groupId
      ? section.exercises.filter((item) => item.supersetGroupId === groupId || item.alternatingGroupId === groupId)
      : [exercise];
    for (const member of members) {
      updateExercise(section.localId, member.localId, { sets, setPrescriptions: concreteSetPrescriptions({ ...member, sets }) });
    }
  }

  const hasDetails =
    exercise.variations.length > 0 ||
    Boolean(exercise.loadProgression) ||
    Object.values(exercise.advanced).some((setting) => setting.enabled) ||
    exercise.setPrescriptions.some((set) => set.note || set.loadValue !== null);

  return (
    <div
      role="row"
      aria-rowindex={index + 1}
      data-testid="structured-exercise-row"
      className="min-w-0"
      style={groupColor ? { borderInlineStart: `3px solid ${groupColor}`, paddingInlineStart: "0.5rem" } : undefined}
    >
      {groupStart ? (
        <div className="pb-1 text-[11px] font-bold uppercase tracking-widest" style={{ color: groupColor ?? "var(--muted)" }}>
          {groupStart === "superset" ? i18n("supersetLabel") : i18n("alternatingSetsLabel")}
        </div>
      ) : null}
      <div className="flex min-w-0 flex-wrap items-center gap-1.5 py-1 sm:flex-nowrap">
        {ctx.intervalMode === "minute" && !heading ? (
          <QuantityField
            {...cellAttributes(key, "interval")}
            aria-label={t("intervalMinute")}
            placeholder={t("intervalMinuteShort")}
            className={`${cellClass} w-14 shrink-0 text-center tabular-nums`}
            fieldStyle={cellStyle}
            value={exercise.intervalAssignment}
            parse={parseCount}
            format={(value) => (value ? String(value) : "")}
            onCommit={(value) => update({ intervalAssignment: value })}
            invalidText={t("invalidCount")}
          />
        ) : null}
        {ctx.intervalMode === "odd_even" && !heading ? (
          <button
            type="button"
            {...cellAttributes(key, "interval")}
            onClick={() => update({ intervalAssignment: exercise.intervalAssignment === null ? 1 : exercise.intervalAssignment === 1 ? 2 : null })}
            className={`${cellClass} w-16 shrink-0 text-center text-xs font-bold`}
            style={cellStyle}
            aria-label={t("oddEvenCycle")}
            title={i18n("clickToCycleBothOddEvene64f8b1")}
          >
            {exercise.intervalAssignment === 1 ? i18n("odddc28f5f") : exercise.intervalAssignment === 2 ? i18n("even9e767ad") : i18n("both1f46983")}
          </button>
        ) : null}

        <Combobox
          {...cellAttributes(key, "name")}
          aria-label={heading ? t("headingName") : t("exerciseName")}
          placeholder={heading ? t("headingPlaceholder") : t("exercisePlaceholder")}
          value={exercise.name}
          onValueChange={(text) => {
            update({ name: text });
            setNameQuery(text);
          }}
          options={suggestions.map((item) => ({
            id: item.id,
            label: item.label,
            hint: item.aliases.length ? item.aliases.slice(0, 2).join(", ") : undefined,
          }))}
          onPick={(option) => {
            update({ name: option.label });
            setNameQuery(null);
          }}
          onBlur={() => setNameQuery(null)}
          listLabel={t("exerciseSuggestions")}
          className={`${cellClass} min-w-[9rem] flex-1 ${heading ? "text-xs font-bold uppercase tracking-widest" : "font-semibold"}`}
          inputStyle={heading ? { ...cellStyle, background: "transparent", borderStyle: "dashed" } : cellStyle}
        />

        {!heading && ctx.showSets ? (
          <QuantityField
            {...cellAttributes(key, "sets")}
            aria-label={t("sets")}
            placeholder={t("setsShort")}
            className={`${cellClass} w-16 shrink-0 text-center tabular-nums`}
            fieldStyle={cellStyle}
            value={exercise.sets > 0 ? exercise.sets : null}
            parse={parseCount}
            format={(value) => (value ? `${value}×` : "")}
            onCommit={(value) => setSets(value ?? 0)}
            invalidText={t("invalidCount")}
            title={grouped ? t("groupSetsHint") : undefined}
          />
        ) : null}

        {!heading && ctx.showClusters ? (
          <QuantityField
            {...cellAttributes(key, "clusters")}
            aria-label={i18n("clustersbc84c52")}
            placeholder={i18n("clustersbc84c52")}
            className={`${cellClass} w-20 shrink-0 text-center tabular-nums`}
            fieldStyle={cellStyle}
            value={exercise.clustersPerSet}
            parse={parseCount}
            format={(value) => (value ? String(value) : "")}
            onCommit={(value) => update({ clustersPerSet: value })}
            invalidText={t("invalidCount")}
          />
        ) : null}

        {!heading && ctx.showPrescription && !ctx.prescriptionHint ? (
          <QuantityField
            {...cellAttributes(key, "rx")}
            aria-label={ctx.ladderPrescription ? (section.format === "pyramid" ? i18n("peakLabel") : i18n("start952f375")) : t("prescription")}
            placeholder={t("prescriptionPlaceholder")}
            className={`${cellClass} w-20 shrink-0 text-center tabular-nums`}
            fieldStyle={cellStyle}
            value={prescription}
            parse={parsePrescription}
            format={(value) => (value ? formatPrescription(value.value, value.unit) : "")}
            onCommit={(value) => update(value ? { prescriptionValue: value.value, prescriptionUnit: value.unit } : { prescriptionValue: 0 })}
            invalidText={t("invalidPrescription")}
          />
        ) : null}
        {!heading && ctx.ladderPrescription ? (
          <QuantityField
            {...cellAttributes(key, "step")}
            aria-label={t("ladderStep")}
            placeholder={section.format === "ladder_descending" ? "−1" : "+1"}
            className={`${cellClass} w-14 shrink-0 text-center tabular-nums`}
            fieldStyle={cellStyle}
            value={exercise.prescriptionStep}
            parse={(text) => parseCount(text.replace(/^[+−-]/, ""))}
            format={(value) => (value ? `${section.format === "ladder_descending" ? "−" : section.format === "pyramid" ? "±" : "+"}${value}` : "")}
            onCommit={(value) => update({ prescriptionStep: value })}
            invalidText={t("invalidCount")}
          />
        ) : null}
        {!heading && ctx.prescriptionHint ? (
          <span className="shrink-0 text-xs italic" style={{ color: "var(--muted)" }}>
            {i18n(ctx.prescriptionHint)}
          </span>
        ) : null}
        {!heading && !ctx.showPrescription && section.format === "train_to_exhaustion" ? (
          <span className="shrink-0 text-xs italic" style={{ color: "var(--muted)" }}>
            {i18n("toFailure1632d91")}
          </span>
        ) : null}

        {!heading && ctx.showLoad ? (
          exercise.loadProgression ? (
            <button
              type="button"
              {...cellAttributes(key, "load")}
              onClick={() => onCommand("details", exercise.localId)}
              className={`${cellClass} w-24 shrink-0 text-xs font-semibold`}
              style={{ ...cellStyle, color: "var(--primary)" }}
              title={t("loadProgressionHint")}
            >
              {i18n("prog095e542")}
            </button>
          ) : (
            <QuantityField
              {...cellAttributes(key, "load")}
              aria-label={t("load")}
              placeholder={t("loadPlaceholder")}
              className={`${cellClass} w-24 shrink-0 text-center tabular-nums`}
              fieldStyle={cellStyle}
              value={load}
              parse={(text) => parseLoad(text, bodyweightLabel)}
              format={(value) => (value ? formatLoad(value.mode, value.value, bodyweightLabel) : "")}
              onCommit={(value) =>
                update(value ? { loadMode: value.mode, loadValue: value.value, isBodyweight: value.mode === "bw" } : { loadMode: "absolute", loadValue: null, isBodyweight: false })
              }
              invalidText={t("invalidLoad")}
            />
          )
        ) : null}

        <div className="flex shrink-0 items-center">
          {!heading ? (
            <button
              type="button"
              onClick={() => onCommand("details", exercise.localId)}
              aria-expanded={detailsOpen}
              aria-label={t("rowDetails")}
              title={`${t("rowDetails")} (${shortcutLabel("details", mac)})`}
              className="flex h-9 w-9 items-center justify-center rounded-full text-sm"
              style={{ color: hasDetails || detailsOpen ? "var(--primary)" : "var(--dim)" }}
            >
              <span aria-hidden="true">{detailsOpen ? "▴" : "▾"}</span>
            </button>
          ) : null}
          <RowMenu
            label={t("rowActions", { name: exercise.name || t("exercisePlaceholder") })}
            items={[
              { id: "moveUp", label: t("moveUp"), onSelect: () => onCommand("moveUp", exercise.localId) },
              { id: "moveDown", label: t("moveDown"), onSelect: () => onCommand("moveDown", exercise.localId) },
              { id: "duplicate", label: t("duplicate"), onSelect: () => onCommand("duplicate", exercise.localId) },
              ...(heading ? [] : [{ id: "superset" as const, label: grouped ? t("leaveGroup") : t("supersetWithAbove"), onSelect: () => onCommand("superset", exercise.localId) }]),
              { id: "note", label: t("addNote"), onSelect: () => onCommand("note", exercise.localId) },
              { id: "deleteRow", label: t("deleteRow"), tone: "danger", onSelect: () => onCommand("delete", exercise.localId) },
            ]}
          />
        </div>
      </div>

      {noteOpen ? (
        <textarea
          {...cellAttributes(key, "note")}
          rows={1}
          aria-label={t("rowNote")}
          placeholder={t("rowNotePlaceholder")}
          value={exercise.note ?? ""}
          onChange={(event) => update({ note: event.target.value || null })}
          className={`${cellClass} mb-1 block w-full resize-y text-xs`}
          style={{ ...cellStyle, background: "transparent" }}
        />
      ) : null}

      {detailsOpen && !heading ? <RowDetails section={section} exercise={exercise} /> : null}
    </div>
  );
}

function RowDetails({ section, exercise }: { section: DraftSection; exercise: DraftExercise }) {
  const t = useTranslations("StructuredWod");
  const i18n = useUiTranslations();
  const { scaleLevels, bodyweightLabel } = useStructuredEditor();
  const sections = useWorkoutCreationStore((state) => state.sections);
  const updateExercise = useWorkoutCreationStore((state) => state.updateExercise);
  const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
  const key = rowKey({ kind: "exercise", sectionId: section.localId, exerciseId: exercise.localId });
  const sets = ctx.showSets ? concreteSetPrescriptions(exercise) : [];

  function updateSet(index: number, patch: Partial<(typeof sets)[number]>) {
    const next = [...sets];
    next[index] = { ...next[index], ...patch };
    updateExercise(section.localId, exercise.localId, { setPrescriptions: next });
  }

  return (
    <div
      className="mb-2 mt-1 overflow-hidden rounded-xl border"
      style={{ borderColor: "var(--border)", background: "var(--panel)" }}
      data-testid="structured-row-details"
    >
      {sets.length > 0 ? (
        <div className="px-3 py-2">
          <div className="mb-1 text-[11px] font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
            {i18n("setDetailsLabel")}
          </div>
          <div className="space-y-1">
            {sets.map((set, index) => (
              <div key={set.setIndex} className="flex min-w-0 flex-wrap items-center gap-1.5">
                <span className="w-12 shrink-0 text-xs font-bold" style={{ color: "var(--dim)" }}>
                  {i18n("setNumberLabel", { number: set.setIndex })}
                </span>
                <QuantityField
                  {...cellAttributes(`${key}:set${set.setIndex}`, "rx")}
                  aria-label={t("setPrescription", { number: set.setIndex })}
                  className={`${cellClass} w-20 text-center tabular-nums`}
                  fieldStyle={cellStyle}
                  value={set.prescriptionValue ? { value: set.prescriptionValue, unit: set.prescriptionUnit ?? exercise.prescriptionUnit } : null}
                  parse={parsePrescription}
                  format={(value) => (value ? formatPrescription(value.value, value.unit) : "")}
                  onCommit={(value) => updateSet(index, { prescriptionValue: value?.value ?? null, prescriptionUnit: value?.unit ?? null })}
                  invalidText={t("invalidPrescription")}
                />
                <QuantityField
                  {...cellAttributes(`${key}:set${set.setIndex}`, "load")}
                  aria-label={t("setLoad", { number: set.setIndex })}
                  className={`${cellClass} w-24 text-center tabular-nums`}
                  fieldStyle={cellStyle}
                  value={set.loadMode === "bw" ? { mode: "bw" as const, value: null } : set.loadValue ? { mode: set.loadMode ?? "absolute", value: set.loadValue } : null}
                  parse={(text) => parseLoad(text, bodyweightLabel)}
                  format={(value) => (value ? formatLoad(value.mode, value.value, bodyweightLabel) : "")}
                  onCommit={(value) => updateSet(index, { loadValue: value?.value ?? null, loadMode: value?.mode ?? null })}
                  invalidText={t("invalidLoad")}
                />
                <input
                  {...cellAttributes(`${key}:set${set.setIndex}`, "note")}
                  type="text"
                  aria-label={t("setNote", { number: set.setIndex })}
                  placeholder={i18n("setNotePlaceholder")}
                  value={set.note ?? ""}
                  onChange={(event) => updateSet(index, { note: event.target.value || null })}
                  className={`${cellClass} min-w-[8rem] flex-1 text-xs`}
                  style={cellStyle}
                />
              </div>
            ))}
          </div>
        </div>
      ) : null}
      <VariationsPanel exercise={exercise} section={section} scaleLevels={scaleLevels} />
      <AdvancedSettingsPanel
        exercise={exercise}
        section={section}
        sectionOptions={sections.map((item) => ({ id: item.localId, name: item.name }))}
      />
    </div>
  );
}
