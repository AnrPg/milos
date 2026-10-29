/**
 * Unsaved edits with undo and redo (ADR-274). A form keeps what the server
 * last said (`saved`) apart from what staff typed (`draft`); nothing reaches
 * the server until they press «Αποθήκευση». `past` and `future` hold whole
 * drafts, so undo and redo never replay partial patches.
 */
export type DraftHistory<T extends Record<string, unknown>> = {
  saved: T;
  draft: T;
  past: T[];
  future: T[];
};

/** Enough for any form; older steps fall off the front. */
export const HISTORY_LIMIT = 100;

export function createDraftHistory<T extends Record<string, unknown>>(saved: T): DraftHistory<T> {
  return { saved, draft: saved, past: [], future: [] };
}

function sameValue(a: unknown, b: unknown) {
  if (Object.is(a, b)) return true;
  if (a && b && typeof a === "object" && typeof b === "object") return JSON.stringify(a) === JSON.stringify(b);
  return false;
}

function sameDraft<T extends Record<string, unknown>>(a: T, b: T) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const key of keys) if (!sameValue(a[key], b[key])) return false;
  return true;
}

/** One step: a patch that changes nothing adds no step. */
export function editDraft<T extends Record<string, unknown>>(history: DraftHistory<T>, patch: Partial<T>): DraftHistory<T> {
  const draft = { ...history.draft, ...patch };
  if (sameDraft(draft, history.draft)) return history;
  return {
    ...history,
    draft,
    past: [...history.past, history.draft].slice(-HISTORY_LIMIT),
    future: [],
  };
}

export function undoDraft<T extends Record<string, unknown>>(history: DraftHistory<T>): DraftHistory<T> {
  const previous = history.past.at(-1);
  if (!previous) return history;
  return { ...history, draft: previous, past: history.past.slice(0, -1), future: [history.draft, ...history.future] };
}

export function redoDraft<T extends Record<string, unknown>>(history: DraftHistory<T>): DraftHistory<T> {
  const [next, ...rest] = history.future;
  if (!next) return history;
  return { ...history, draft: next, past: [...history.past, history.draft], future: rest };
}

/** «Ακύρωση»: back to what the server has. */
export function discardDraft<T extends Record<string, unknown>>(history: DraftHistory<T>): DraftHistory<T> {
  return createDraftHistory(history.saved);
}

/** After a save: what was sent is now what the server has. */
export function commitDraft<T extends Record<string, unknown>>(history: DraftHistory<T>, saved: T = history.draft): DraftHistory<T> {
  return createDraftHistory(saved);
}

/**
 * The server's copy changed under the form (a refetch, another action such
 * as leaving the box). Fields staff have not touched follow the server; the
 * ones they changed keep their edit, so a refresh never eats typing.
 */
export function rebaseDraft<T extends Record<string, unknown>>(history: DraftHistory<T>, saved: T): DraftHistory<T> {
  if (sameDraft(saved, history.saved)) return history;
  const touched = changedKeys(history);
  if (touched.length === 0) return createDraftHistory(saved);
  const draft = { ...saved };
  for (const key of touched) (draft as Record<string, unknown>)[key] = history.draft[key];
  return { ...history, saved, draft };
}

export function changedKeys<T extends Record<string, unknown>>(history: DraftHistory<T>): Array<keyof T & string> {
  const keys = new Set([...Object.keys(history.saved), ...Object.keys(history.draft)]);
  return [...keys].filter((key) => !sameValue(history.saved[key], history.draft[key])) as Array<keyof T & string>;
}

/** Only the changed fields, for a PATCH. */
export function changedPatch<T extends Record<string, unknown>>(history: DraftHistory<T>): Partial<T> {
  const patch: Partial<T> = {};
  for (const key of changedKeys(history)) patch[key] = history.draft[key];
  return patch;
}

export function isDirty<T extends Record<string, unknown>>(history: DraftHistory<T>) {
  return changedKeys(history).length > 0;
}
