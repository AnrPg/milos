"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useTranslations } from "next-intl";

import { Dialog } from "@/components/ui/Dialog";
import { SaveBar } from "@/components/ui/SaveBar";
import {
  changedKeys,
  commitDraft,
  createDraftHistory,
  discardDraft,
  editDraft,
  rebaseDraft,
  redoDraft,
  undoDraft,
  type DraftHistory,
} from "@/lib/draft-history";

/**
 * Unsaved edits on a page of forms (ADR-274). Each form keeps a draft with
 * `useDraftForm`; the page shows ONE SaveBar for all of them (`PageSaveBar`):
 * the change count adds up, undo and redo walk the edits in the order they
 * were made across forms, «Ακύρωση» drops every draft and «Αποθήκευση» saves
 * the changed forms one after another. Before anything unmounts the forms
 * (another tab, a section link) the page calls `guard(action)`, which asks
 * stay / discard / save first. Closing or reloading the browser tab gets
 * the browser's warning. A form outside such a page shows its own bar.
 */

type FormApi = {
  changes: () => number;
  canUndo: () => boolean;
  canRedo: () => boolean;
  undo: () => void;
  redo: () => void;
  discard: () => void;
  save: () => Promise<boolean>;
  saving: () => boolean;
  error: () => ReactNode;
};

type Forms = {
  register: (id: string, api: { current: FormApi }) => () => void;
  /** A form's snapshot changed: the page bar re-renders. */
  refresh: () => void;
  edited: (id: string) => void;
  /** The form dropped or saved its draft: its steps leave the shared stacks. */
  reset: (id: string) => void;
  saved: () => void;
};

const FormsContext = createContext<Forms | null>(null);

export function useDraftForms() {
  const forms = useRef(new Map<string, { current: FormApi }>());
  const undoStack = useRef<string[]>([]);
  const redoStack = useRef<string[]>([]);
  const [snapshot, setSnapshot] = useState<{ changes: number; canUndo: boolean; canRedo: boolean; saving: boolean; error: ReactNode }>({
    changes: 0,
    canUndo: false,
    canRedo: false,
    saving: false,
    error: null,
  });
  const [justSaved, setJustSaved] = useState(false);
  const [pending, setPending] = useState<(() => void) | null>(null);
  const [savingAll, setSavingAll] = useState(false);

  const all = useCallback(() => [...forms.current.values()].map((form) => form.current), []);
  const dirty = useCallback(() => all().filter((form) => form.changes() > 0), [all]);
  // Read from the forms outside render (effects and handlers), kept as state.
  const refresh = useCallback(() => {
    const current = [...forms.current.values()].map((form) => form.current);
    const next = {
      changes: current.reduce((sum, form) => sum + form.changes(), 0),
      canUndo: undoStack.current.length > 0,
      canRedo: redoStack.current.length > 0,
      saving: current.some((form) => form.saving()),
      error: current.map((form) => form.error()).find(Boolean) ?? null,
    };
    setSnapshot((previous) =>
      previous.changes === next.changes &&
      previous.canUndo === next.canUndo &&
      previous.canRedo === next.canRedo &&
      previous.saving === next.saving &&
      previous.error === next.error
        ? previous
        : next,
    );
  }, []);

  useEffect(() => {
    function onBeforeUnload(event: BeforeUnloadEvent) {
      if (dirty().length === 0) return;
      event.preventDefault();
      event.returnValue = "";
    }
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [dirty]);

  const context = useMemo<Forms>(
    () => ({
      register(id, api) {
        forms.current.set(id, api);
        refresh();
        return () => {
          if (forms.current.get(id) !== api) return;
          forms.current.delete(id);
          undoStack.current = undoStack.current.filter((item) => item !== id);
          redoStack.current = redoStack.current.filter((item) => item !== id);
          refresh();
        };
      },
      refresh,
      edited(id) {
        undoStack.current = [...undoStack.current, id];
        redoStack.current = [];
        setJustSaved(false);
        refresh();
      },
      reset(id) {
        undoStack.current = undoStack.current.filter((item) => item !== id);
        redoStack.current = redoStack.current.filter((item) => item !== id);
        refresh();
      },
      saved: () => setJustSaved(true),
    }),
    [refresh],
  );

  const undo = useCallback(() => {
    const id = undoStack.current.at(-1);
    const form = id ? forms.current.get(id)?.current : undefined;
    if (!id || !form) return;
    undoStack.current = undoStack.current.slice(0, -1);
    redoStack.current = [...redoStack.current, id];
    form.undo();
    refresh();
  }, [refresh]);
  const redo = useCallback(() => {
    const id = redoStack.current.at(-1);
    const form = id ? forms.current.get(id)?.current : undefined;
    if (!id || !form) return;
    redoStack.current = redoStack.current.slice(0, -1);
    undoStack.current = [...undoStack.current, id];
    form.redo();
    refresh();
  }, [refresh]);
  const discardAll = useCallback(() => {
    for (const form of all()) form.discard();
    undoStack.current = [];
    redoStack.current = [];
    refresh();
  }, [all, refresh]);
  const saveAll = useCallback(async () => {
    setSavingAll(true);
    try {
      // A failed save (or one that needs more input, like a reason) stops
      // here; its form shows why and keeps its draft.
      for (const form of dirty()) if (!(await form.save())) return false;
      setJustSaved(true);
      return true;
    } finally {
      setSavingAll(false);
    }
  }, [dirty]);

  const guard = useCallback(
    (action: () => void) => {
      if (dirty().length === 0) action();
      else setPending(() => action);
    },
    [dirty],
  );

  const bar = {
    ...snapshot,
    saving: savingAll || snapshot.saving,
    saved: justSaved,
    onUndo: undo,
    onRedo: redo,
    onCancel: discardAll,
    onSave: () => void saveAll(),
  };

  const prompt = pending
    ? {
        saving: savingAll,
        stay: () => setPending(null),
        discardAndGo: () => {
          discardAll();
          setPending(null);
          pending();
        },
        saveAndGo: async () => {
          const ok = await saveAll();
          setPending(null);
          if (ok) pending();
        },
      }
    : null;

  return { context, guard, bar, prompt };
}

export function DraftFormsProvider({ value, children }: { value: Forms; children: ReactNode }) {
  return <FormsContext.Provider value={value}>{children}</FormsContext.Provider>;
}

/** The page's one bar for every form under the provider. */
export function PageSaveBar({ bar, testId = "profile-save-bar" }: { bar: ReturnType<typeof useDraftForms>["bar"]; testId?: string }) {
  return <SaveBar {...bar} placement="page" testId={testId} />;
}

/**
 * One form's draft. `save` gets the draft (and any argument the caller
 * passes, such as a reason) and throws on failure; `describeError` turns
 * the failure into what the bar shows (null: the form shows it itself).
 */
export function useDraftForm<T extends Record<string, unknown>, A = void>({
  server,
  save,
  describeError,
  onSaved,
  count,
  testId,
}: {
  server: T;
  save: (draft: T, history: DraftHistory<T>, arg?: A) => Promise<unknown>;
  describeError: (error: unknown) => ReactNode;
  onSaved?: () => Promise<unknown> | void;
  /** How many changes the bar counts; defaults to one per changed field. */
  count?: (history: DraftHistory<T>) => number;
  testId?: string;
}) {
  const forms = useContext(FormsContext);
  const id = useId();
  const serverKey = JSON.stringify(server);
  const [syncedKey, setSyncedKey] = useState(serverKey);
  const [history, setHistory] = useState(() => createDraftHistory(server));
  // The server copy follows refetches without eating fields still edited.
  if (syncedKey !== serverKey) {
    setSyncedKey(serverKey);
    setHistory((current) => rebaseDraft(current, server));
  }
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [savedAlone, setSavedAlone] = useState(false);
  const changed = useMemo(() => new Set<string>(changedKeys(history)), [history]);
  const changes = count ? count(history) : changed.size;

  const historyRef = useRef(history);
  useEffect(() => {
    historyRef.current = history;
  });
  const apply = useCallback((next: DraftHistory<T>) => {
    historyRef.current = next;
    setHistory(next);
  }, []);

  const edit = useCallback(
    (patch: Partial<T>) => {
      const next = editDraft(historyRef.current, patch);
      if (next === historyRef.current) return;
      setSavedAlone(false);
      setError(null);
      apply(next);
      forms?.edited(id);
    },
    [apply, forms, id],
  );
  const undo = useCallback(() => apply(undoDraft(historyRef.current)), [apply]);
  const redo = useCallback(() => apply(redoDraft(historyRef.current)), [apply]);
  const discard = useCallback(() => {
    setError(null);
    apply(discardDraft(historyRef.current));
    forms?.reset(id);
  }, [apply, forms, id]);
  const run = useCallback(
    async (arg?: A) => {
      const sent = historyRef.current;
      setSaving(true);
      setError(null);
      try {
        await save(sent.draft, sent, arg);
        // Fields are disabled while saving, so what was sent is the draft.
        apply(commitDraft(sent));
        forms?.reset(id);
        forms?.saved();
        setSavedAlone(true);
        await onSaved?.();
        return true;
      } catch (failure) {
        setError(failure ?? new Error());
        return false;
      } finally {
        setSaving(false);
      }
    },
    [apply, forms, id, onSaved, save],
  );

  const errorNode = error ? describeError(error) : null;
  const api = useRef<FormApi>({
    changes: () => 0,
    canUndo: () => false,
    canRedo: () => false,
    undo,
    redo,
    discard,
    save: () => run(),
    saving: () => false,
    error: () => null,
  });
  useEffect(() => {
    api.current = {
      changes: () => changes,
      canUndo: () => history.past.length > 0,
      canRedo: () => history.future.length > 0,
      undo,
      redo,
      discard,
      save: () => run(),
      saving: () => saving,
      error: () => errorNode,
    };
  });
  useEffect(() => forms?.register(id, api), [forms, id]);
  const snapshot = `${changes}|${history.past.length}|${history.future.length}|${saving}|${Boolean(errorNode)}`;
  useEffect(() => {
    forms?.refresh();
  }, [forms, snapshot]);

  const bar = forms ? null : (
    <SaveBar
      testId={testId}
      changes={changes}
      canUndo={history.past.length > 0}
      canRedo={history.future.length > 0}
      onUndo={undo}
      onRedo={redo}
      onCancel={discard}
      onSave={() => void run()}
      saving={saving}
      saved={savedAlone}
      error={errorNode}
    />
  );

  /** True after this form's last save, until the next edit. */
  const justSaved = savedAlone;
  return { draft: history.draft, history, changed, edit, saving, error, justSaved, save: run, discard, bar };
}

export function UnsavedChangesDialog({ prompt }: { prompt: ReturnType<typeof useDraftForms>["prompt"] }) {
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
            onClick={() => void prompt.saveAndGo()}
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
