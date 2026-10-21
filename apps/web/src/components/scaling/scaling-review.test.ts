import { describe, expect, it } from "vitest";

import type { ScalingSuggestionItem } from "@/api/scaling";
import { approvableCount, approveBody, emptyDraft } from "@/components/scaling/scaling-review";

const items: ScalingSuggestionItem[] = [
  { id: "i1", exercise_id: "m1", exercise_name: "Back Squat", change: "substitute", suggested: "Box squat", reason: "Less knee flexion" },
  { id: "i2", exercise_id: "m2", exercise_name: "Box jump", change: "skip", suggested: null, reason: "Impact" },
];

describe("scaling review", () => {
  it("approves everything as proposed when the coach changed nothing", () => {
    expect(approveBody(items, emptyDraft())).toEqual({});
    expect(approvableCount(items, "scaled", emptyDraft())).toBe(3);
  });

  it("sends only the coach's edits, trimmed and capped", () => {
    const draft = {
      ...emptyDraft(),
      excluded: { i2: true },
      suggested: { i1: "  Goblet squat  " },
      dropScale: true,
      note: "  Easy today  ",
    };
    expect(approveBody(items, draft)).toEqual({
      items: [
        { id: "i1", suggested: "Goblet squat" },
        { id: "i2", include: false },
      ],
      scale_level_slug: null,
      coach_note: "Easy today",
    });
  });

  it("ignores an edit that equals the proposal", () => {
    const draft = { ...emptyDraft(), suggested: { i1: "Box squat " } };
    expect(approveBody(items, draft)).toEqual({});
  });

  it("has nothing to approve once every change and the level are dropped", () => {
    const draft = { ...emptyDraft(), excluded: { i1: true, i2: true }, dropScale: true };
    expect(approvableCount(items, "scaled", draft)).toBe(0);
    expect(approvableCount(items, null, { ...draft, dropScale: false })).toBe(0);
  });
});
