"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * The bar that holds a form's unsaved edits (ADR-274). It shows only while
 * something changed: how many fields, undo, redo, «Ακύρωση» and
 * «Αποθήκευση». After a save it says so once, then goes away. It sticks to
 * the bottom of the screen inside its panel, so the actions stay in reach
 * on a long tab.
 *
 * Ctrl/⌘+S saves, Ctrl/⌘+Z undoes and Ctrl/⌘+Shift+Z (or Ctrl+Y) redoes,
 * except inside a text field, where the browser's own undo applies.
 */
export function SaveBar({
  changes,
  canUndo,
  canRedo,
  onUndo,
  onRedo,
  onCancel,
  onSave,
  saving = false,
  saved = false,
  error,
  placement = "panel",
  testId = "save-bar",
}: {
  changes: number;
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;
  onCancel: () => void;
  onSave: () => void;
  saving?: boolean;
  /** True right after a save, until the next edit. */
  saved?: boolean;
  error?: ReactNode;
  /** "panel": the bottom edge of a padded panel; "page": a floating card at the bottom of the page. */
  placement?: "panel" | "page";
  testId?: string;
}) {
  const t = useTranslations("SaveBar");
  const handlers = useRef({ onUndo, onRedo, onSave, canUndo, canRedo, changes, saving });
  useEffect(() => {
    handlers.current = { onUndo, onRedo, onSave, canUndo, canRedo, changes, saving };
  });

  const active = changes > 0 || canRedo;
  useEffect(() => {
    if (!active) return;
    function onKeyDown(event: KeyboardEvent) {
      if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
      const key = event.key.toLowerCase();
      const current = handlers.current;
      if (key === "s") {
        event.preventDefault();
        if (current.changes > 0 && !current.saving) current.onSave();
        return;
      }
      if (isTextField(event.target)) return;
      const redo = (key === "z" && event.shiftKey) || (key === "y" && !event.shiftKey);
      if (redo) {
        if (!current.canRedo) return;
        event.preventDefault();
        current.onRedo();
      } else if (key === "z") {
        if (!current.canUndo) return;
        event.preventDefault();
        current.onUndo();
      }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [active]);

  if (!active && !saved && !error) return null;

  const iconButton = "grid h-11 w-11 shrink-0 place-items-center rounded-full disabled:opacity-40";
  const iconStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <div
      className={
        placement === "page"
          ? "sticky bottom-[max(1rem,env(safe-area-inset-bottom))] z-(--z-sticky) rounded-[1.5rem] border px-5 py-3.5"
          : "sticky bottom-0 z-(--z-sticky) -mx-6 -mb-6 mt-4 border-t px-6 pb-[max(0.875rem,env(safe-area-inset-bottom))] pt-3.5"
      }
      style={{ background: "var(--panel)", borderColor: "var(--border)", boxShadow: "var(--shadow-md)" }}
      data-testid={testId}
    >
      {active ? (
        <div role="region" aria-label={t("region")} className="flex flex-wrap items-center gap-3">
          <span className="flex min-w-0 flex-1 items-center gap-2 font-semibold" style={{ color: "var(--text)" }}>
            {changes > 0 ? <span aria-hidden className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: "var(--warning)" }} /> : null}
            <span data-testid={`${testId}-count`}>{changes > 0 ? t("unsaved", { count: changes }) : t("noChanges")}</span>
          </span>
          <button type="button" className={iconButton} style={iconStyle} disabled={!canUndo || saving} onClick={onUndo} aria-label={t("undo")} title={t("undoHint")}>
            <svg aria-hidden viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M7 5 3 9l4 4" /><path d="M3 9h9a5 5 0 0 1 0 10h-2" /></svg>
          </button>
          <button type="button" className={iconButton} style={iconStyle} disabled={!canRedo || saving} onClick={onRedo} aria-label={t("redo")} title={t("redoHint")}>
            <svg aria-hidden viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="m13 5 4 4-4 4" /><path d="M17 9H8a5 5 0 0 0 0 10h2" /></svg>
          </button>
          <button
            type="button"
            className="min-h-11 rounded-full px-[1.125rem] text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
            disabled={changes === 0 || saving}
            onClick={onCancel}
          >
            {t("cancel")}
          </button>
          <button
            type="button"
            className="min-h-11 rounded-full px-[1.375rem] text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={changes === 0 || saving}
            onClick={onSave}
            data-testid={`${testId}-save`}
          >
            {saving ? t("saving") : t("save")}
          </button>
        </div>
      ) : null}
      {error ? <ErrorNotice variant="field" className={active ? "mt-2" : undefined}>{error}</ErrorNotice> : null}
      {!active && saved && !error ? (
        <p role="status" className="font-semibold" style={{ color: "var(--success)" }}>
          {t("saved")}
        </p>
      ) : null}
    </div>
  );
}

function isTextField(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable || target instanceof HTMLTextAreaElement) return true;
  if (!(target instanceof HTMLInputElement)) return false;
  return !["checkbox", "radio", "button", "submit", "reset", "range", "color", "file"].includes(target.type);
}
