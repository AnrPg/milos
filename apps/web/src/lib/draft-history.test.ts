import { describe, expect, it } from "vitest";

import {
  HISTORY_LIMIT,
  changedKeys,
  changedPatch,
  commitDraft,
  createDraftHistory,
  discardDraft,
  editDraft,
  isDirty,
  rebaseDraft,
  redoDraft,
  undoDraft,
} from "./draft-history";

const saved = { status: "trial", starts_on: "2026-10-29", expires_on: "" };

describe("draft history (ADR-274)", () => {
  it("keeps edits apart from the saved copy and lists only what changed", () => {
    const history = editDraft(createDraftHistory(saved), { expires_on: "2026-11-28" });
    expect(history.saved).toEqual(saved);
    expect(isDirty(history)).toBe(true);
    expect(changedKeys(history)).toEqual(["expires_on"]);
    expect(changedPatch(history)).toEqual({ expires_on: "2026-11-28" });
  });

  it("adds no step for a patch that changes nothing", () => {
    const start = createDraftHistory(saved);
    expect(editDraft(start, { status: "trial" })).toBe(start);
  });

  it("undoes and redoes whole steps, and a new edit clears redo", () => {
    let history = createDraftHistory(saved);
    history = editDraft(history, { status: "active" });
    history = editDraft(history, { expires_on: "2026-11-28" });
    history = undoDraft(history);
    expect(history.draft).toEqual({ ...saved, status: "active" });
    history = undoDraft(history);
    expect(history.draft).toEqual(saved);
    expect(isDirty(history)).toBe(false);
    history = redoDraft(history);
    expect(history.draft.status).toBe("active");
    history = editDraft(history, { starts_on: "2026-11-01" });
    expect(history.future).toEqual([]);
    expect(redoDraft(history)).toBe(history);
  });

  it("does nothing on undo or redo with no steps", () => {
    const start = createDraftHistory(saved);
    expect(undoDraft(start)).toBe(start);
    expect(redoDraft(start)).toBe(start);
  });

  it("goes back to the saved copy on discard and adopts the draft on commit", () => {
    const edited = editDraft(createDraftHistory(saved), { status: "paused" });
    expect(discardDraft(edited)).toEqual(createDraftHistory(saved));
    const committed = commitDraft(edited);
    expect(committed.saved.status).toBe("paused");
    expect(isDirty(committed)).toBe(false);
    expect(committed.past).toEqual([]);
  });

  it("follows the server for untouched fields and keeps the ones staff changed", () => {
    const edited = editDraft(createDraftHistory(saved), { starts_on: "2026-11-01" });
    const rebased = rebaseDraft(edited, { ...saved, status: "active", expires_on: "2026-12-01" });
    expect(rebased.draft).toEqual({ status: "active", starts_on: "2026-11-01", expires_on: "2026-12-01" });
    expect(changedKeys(rebased)).toEqual(["starts_on"]);
    expect(rebaseDraft(createDraftHistory(saved), { ...saved, status: "active" })).toEqual(createDraftHistory({ ...saved, status: "active" }));
  });

  it("returns the same history when the server copy did not change", () => {
    const edited = editDraft(createDraftHistory(saved), { status: "active" });
    expect(rebaseDraft(edited, { ...saved })).toBe(edited);
  });

  it("compares nested values by content", () => {
    const start = createDraftHistory({ renew: { a: true } as Record<string, boolean> });
    expect(editDraft(start, { renew: { a: true } })).toBe(start);
    expect(changedKeys(editDraft(start, { renew: { a: false } }))).toEqual(["renew"]);
  });

  it("caps the undo steps", () => {
    let history = createDraftHistory({ n: 0 });
    for (let n = 1; n <= HISTORY_LIMIT + 5; n += 1) history = editDraft(history, { n });
    expect(history.past).toHaveLength(HISTORY_LIMIT);
  });
});
