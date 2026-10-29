"use client";

import { createContext, useCallback, useContext, useEffect, useId, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { Dialog } from "@/components/ui/Dialog";

/**
 * Unsaved edits must not vanish silently (ADR-274). A form with a SaveBar
 * registers here; before anything unmounts it (another tab, a section link)
 * the page calls `guard(action)`, which runs the action at once when nothing
 * is unsaved and otherwise asks: stay, discard, or save and go on. Closing
 * or reloading the browser tab gets the browser's own warning.
 */
export type UnsavedSource = {
  dirty: () => boolean;
  /** Resolves true when the save went through. */
  save: () => Promise<boolean>;
  discard: () => void;
};

type Registry = { register: (id: string, source: { current: UnsavedSource }) => () => void };

const UnsavedContext = createContext<Registry | null>(null);

export function useUnsavedChanges() {
  const sources = useRef(new Map<string, { current: UnsavedSource }>());
  const [pending, setPending] = useState<(() => void) | null>(null);
  const [saving, setSaving] = useState(false);

  const dirtySources = useCallback(() => [...sources.current.values()].filter((source) => source.current.dirty()), []);

  useEffect(() => {
    function onBeforeUnload(event: BeforeUnloadEvent) {
      if (dirtySources().length === 0) return;
      event.preventDefault();
      event.returnValue = "";
    }
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [dirtySources]);

  const registry = useMemo<Registry>(
    () => ({
      register(id, source) {
        sources.current.set(id, source);
        return () => {
          if (sources.current.get(id) === source) sources.current.delete(id);
        };
      },
    }),
    [],
  );

  const guard = useCallback(
    (action: () => void) => {
      if (dirtySources().length === 0) action();
      else setPending(() => action);
    },
    [dirtySources],
  );

  const stay = useCallback(() => setPending(null), []);
  const discardAndGo = useCallback(() => {
    for (const source of dirtySources()) source.current.discard();
    const action = pending;
    setPending(null);
    action?.();
  }, [dirtySources, pending]);
  const saveAndGo = useCallback(async () => {
    setSaving(true);
    try {
      for (const source of dirtySources()) {
        // A failed save (or one that needs more input, like a reason) keeps
        // the person here, with the error shown in the form's bar.
        if (!(await source.current.save())) {
          setPending(null);
          return;
        }
      }
      const action = pending;
      setPending(null);
      action?.();
    } finally {
      setSaving(false);
    }
  }, [dirtySources, pending]);

  return { registry, guard, prompt: pending ? { saving, stay, discardAndGo, saveAndGo } : null };
}

export function UnsavedChangesProvider({ registry, children }: { registry: Registry; children: ReactNode }) {
  return <UnsavedContext.Provider value={registry}>{children}</UnsavedContext.Provider>;
}

/** A form's side: keeps the latest callbacks without re-registering. */
export function useRegisterUnsaved(source: UnsavedSource) {
  const registry = useContext(UnsavedContext);
  const id = useId();
  const latest = useRef(source);
  useEffect(() => {
    latest.current = source;
  });
  useEffect(() => registry?.register(id, latest), [registry, id]);
}

export function UnsavedChangesDialog({
  prompt,
}: {
  prompt: { saving: boolean; stay: () => void; discardAndGo: () => void; saveAndGo: () => void } | null;
}) {
  const t = useTranslations("SaveBar");
  if (!prompt) return null;
  return (
    <Dialog
      onClose={prompt.stay}
      title={t("leaveTitle")}
      size="md"
      variant="center"
      dismissible={!prompt.saving}
      testId="unsaved-changes-dialog"
      footer={
        <>
          <button
            type="button"
            className="min-h-11 rounded-full px-4 text-sm font-semibold"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
            disabled={prompt.saving}
            onClick={prompt.stay}
          >
            {t("leaveStay")}
          </button>
          <button
            type="button"
            className="min-h-11 rounded-full px-4 text-sm font-semibold"
            style={{ background: "var(--danger-surface)", border: "1px solid var(--danger-border)", color: "var(--danger-strong)" }}
            disabled={prompt.saving}
            onClick={prompt.discardAndGo}
          >
            {t("leaveDiscard")}
          </button>
          <button
            type="button"
            className="min-h-11 rounded-full px-[1.125rem] text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={prompt.saving}
            onClick={prompt.saveAndGo}
          >
            {prompt.saving ? t("saving") : t("save")}
          </button>
        </>
      }
    >
      <p style={{ color: "var(--text-soft)" }}>{t("leaveBody")}</p>
    </Dialog>
  );
}
