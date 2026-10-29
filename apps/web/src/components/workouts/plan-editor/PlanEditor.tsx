"use client";

import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore, type KeyboardEvent } from "react";

import { focusKey, hasExercises, usePlanEditorStore } from "@/stores/structured-plan";

import { HintBar } from "./HintBar";
import { isMacPlatform, keyLabel, matchPlanShortcut } from "./keymap";
import { OpenSection } from "./OpenSection";
import { SectionCard } from "./SectionCard";
import { ShortcutsSheet } from "./ShortcutsSheet";
import { noteFieldClass, noteFieldStyle, type PlanLevel } from "./StepScore";

const noSubscribe = () => () => {};
const STATUS_MS = 2500;

/** Fields of the wizard steps where Enter moves on (next field, then the next step). */
const STEP_FIELD = /^(p|score|snote|sname|lnote):/;
/** Row fields (grid): `r:<rowId>:…` or `c:<rowId>:…`. */
const ROW_FIELD = /^(?:r|c):([^:]+)/;

function focusables(root: HTMLElement, selector: string): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(selector)].filter((el) => !(el as HTMLButtonElement).disabled);
}

/**
 * ADR-270: the structured WOD editor (alternative A of the approved mockup,
 * the per-section wizard). WOD title and note, the sections as closed cards
 * with one open at a time, «+ Ενότητα», a bottom hint line and the shortcut
 * sheet. One key handler serves the whole editor; the exercise grid may
 * handle a key first and `preventDefault()` it.
 *
 * State lives in `usePlanEditorStore`; the caller loads it (`load`) and reads
 * it back (`serialize`). `levels` are the workout's scale levels for
 * per-level notes.
 */
export function PlanEditor({ levels }: { levels?: PlanLevel[] }) {
  const t = useTranslations("PlanEditor");
  const title = usePlanEditorStore((s) => s.title);
  const note = usePlanEditorStore((s) => s.note);
  const sections = usePlanEditorStore((s) => s.sections);
  const openId = usePlanEditorStore((s) => s.openId);
  const step = usePlanEditorStore((s) => s.step);
  const pendingFocus = usePlanEditorStore((s) => s.pendingFocus);
  const setTitle = usePlanEditorStore((s) => s.setTitle);
  const setNote = usePlanEditorStore((s) => s.setNote);
  const addSection = usePlanEditorStore((s) => s.addSection);
  const mac = useSyncExternalStore(noSubscribe, isMacPlatform, () => false);
  const [sheet, setSheet] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const statusTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const say = useCallback((text: string) => {
    setStatus(text);
    if (statusTimer.current) clearTimeout(statusTimer.current);
    statusTimer.current = setTimeout(() => setStatus(null), STATUS_MS);
  }, []);
  useEffect(() => () => {
    if (statusTimer.current) clearTimeout(statusTimer.current);
  }, []);

  // Moves focus to the field a mutation asked for, once it is on screen.
  useEffect(() => {
    const root = rootRef.current;
    if (!pendingFocus || !root) return;
    // The grid marks its fields with `data-key`, the shell with `data-k`; both use the store's focus keys.
    const el = [...root.querySelectorAll<HTMLElement>("[data-k], [data-key]")].find((x) => (x.dataset.k ?? x.dataset.key) === pendingFocus);
    if (!el) return;
    usePlanEditorStore.getState().consumeFocus(pendingFocus);
    el.focus();
    if (el instanceof HTMLInputElement) el.select();
  }, [pendingFocus, sections, openId, step]);

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.defaultPrevented || sheet) return;
    const root = rootRef.current;
    const target = e.target as HTMLElement;
    const k = target.dataset?.k ?? target.dataset?.key ?? "";
    const inText = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target.isContentEditable;
    const store = usePlanEditorStore.getState();

    // Closed cards: ↑ ↓ move between them (and into the open section).
    if (k.startsWith("card:") && (e.key === "ArrowDown" || e.key === "ArrowUp") && !e.altKey && root) {
      e.preventDefault();
      const stops = [...root.querySelectorAll<HTMLElement>("[data-k^='card:'], [data-sec]")];
      const next = stops[stops.indexOf(target) + (e.key === "ArrowDown" ? 1 : -1)];
      (next?.dataset.sec ? focusables(next, "input, button")[0] : next)?.focus();
      return;
    }

    const hit = matchPlanShortcut(e.nativeEvent, { mac, inText });
    if (!hit) return;
    const done = () => e.preventDefault();

    switch (hit.id) {
      case "undo":
        done();
        store.undo();
        say(t("status.undone"));
        return;
      case "redo":
        done();
        store.redo();
        say(t("status.redone"));
        return;
      case "sheet":
        done();
        setSheet(true);
        return;
      case "newSection":
        done();
        store.addSection(store.openId ?? store.sections.at(-1)?.id ?? null);
        return;
    }

    if (k.startsWith("card:")) {
      const id = k.slice(5);
      if (hit.id === "moveSectionUp" || hit.id === "moveSectionDown") {
        done();
        store.moveSection(id, hit.id === "moveSectionUp" ? -1 : 1);
        store.setFocus(focusKey.card(id));
      }
      return;
    }
    if (k === "w:title" && hit.id === "newExercise" && root) {
      done();
      root.querySelector<HTMLElement>("[data-k^='card:'], [data-sec] input")?.focus();
      return;
    }

    const open = store.sections.find((s) => s.id === store.openId);
    if (!open || !target.closest(`[data-sec="${open.id}"]`)) return;

    switch (hit.id) {
      case "close":
        done();
        store.closeSection();
        return;
      case "nextStep":
        done();
        store.nextStep();
        return;
      case "prevStep":
        done();
        store.prevStep();
        return;
      case "jumpStep":
        done();
        store.setStep(hit.step as 0 | 1 | 2 | 3);
        return;
      case "differentRound":
        if (!hasExercises(open.plan.flow)) return;
        done();
        if (store.step !== 2) store.setStep(2);
        store.addBlock(open.id);
        return;
    }

    // Wizard fields: Enter goes to the next field, then the next step.
    if (STEP_FIELD.test(k) && hit.id === "newExercise") {
      done();
      const fields = root ? focusables(root.querySelector(`[data-sec="${open.id}"]`) ?? root, "[data-k^='p:'], [data-k^='score:'], [data-k^='snote:'], [data-k^='lnote:']") : [];
      const next = fields[fields.indexOf(target) + 1];
      if (next) {
        next.focus();
        if (next instanceof HTMLInputElement) next.select();
      } else store.nextStep();
      return;
    }
    if (hit.id === "note" && !ROW_FIELD.test(k)) {
      done();
      store.setStep(3);
      store.setFocus(focusKey.sectionNote(open.id));
      return;
    }

    const row = ROW_FIELD.exec(k);
    const rowId = row?.[1];
    if (!rowId || !store.findRow(rowId)) return;
    switch (hit.id) {
      case "newExercise":
        done();
        store.addRow(rowId);
        return;
      case "superset":
        done();
        store.toggleSuperset(rowId);
        return;
      case "rest":
        done();
        store.addRow(rowId, "rest");
        return;
      case "perRound":
        done();
        if (!store.togglePerRound(rowId)) say(t("perRoundOnce"));
        return;
      case "deleteRow":
        if (k.endsWith(":name") && target instanceof HTMLInputElement && target.value === "") {
          done();
          store.deleteRow(rowId);
          say(t("deleted", { undo: keyLabel("Mod+Z", mac) }));
        }
        return;
      default:
        // Alt+M, Alt+P, Alt+T, Alt+N on a row open the grid's own menus.
        return;
    }
  };

  const openIndex = sections.findIndex((s) => s.id === openId);

  return (
    <div ref={rootRef} data-testid="plan-editor" aria-label={t("label")} onKeyDown={onKeyDown} className="flex min-w-0 flex-col gap-3" style={{ color: "var(--text)" }}>
      <input
        data-testid="plan-title"
        data-k="w:title"
        value={title}
        placeholder={t("titlePlaceholder")}
        aria-label={t("title")}
        onChange={(e) => setTitle(e.target.value)}
        className="w-full min-w-0 rounded-lg border border-transparent bg-transparent px-1.5 py-1 text-xl font-extrabold outline-none focus:border-[var(--primary)]"
        style={{ color: "var(--text)" }}
      />
      <input
        data-testid="plan-wod-note"
        data-k="w:note"
        value={note}
        placeholder={t("wodNote")}
        aria-label={t("wodNote")}
        onChange={(e) => setNote({ kind: "wod" }, e.target.value)}
        className={noteFieldClass}
        style={{ ...noteFieldStyle, borderStyle: "dashed" }}
      />
      <div className="flex min-w-0 flex-col gap-2">
        {sections.map((section, i) =>
          section.id === openId ? (
            <OpenSection key={section.id} section={section} index={i} step={step} levels={levels} />
          ) : (
            <SectionCard key={section.id} section={section} index={i} />
          ),
        )}
      </div>
      <div>
        <button
          type="button"
          data-testid="plan-add-section"
          onClick={() => addSection(openId ?? sections.at(-1)?.id ?? null)}
          title={keyLabel("Shift+Enter", mac)}
          className="rounded-full border border-dashed px-4 py-1.5 text-sm font-semibold max-sm:min-h-10"
          style={{ borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
        >
          {t("addSection")}
        </button>
      </div>
      <HintBar open={openIndex >= 0} step={step} mac={mac} status={status} />
      {sheet ? <ShortcutsSheet mac={mac} onClose={() => setSheet(false)} /> : null}
    </div>
  );
}
