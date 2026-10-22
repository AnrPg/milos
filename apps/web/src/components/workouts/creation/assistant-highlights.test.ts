import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { AnalysisIssue } from "@/lib/free-text-analysis";

import {
  AssistantHighlights,
  anchoredIssues,
  assistantHighlightsKey,
  locateMarks,
  markCategory,
  marksAt,
} from "./assistant-highlights";

const issue = (id: string, anchor: string | null, extra: Partial<AnalysisIssue> = {}) =>
  ({ id, anchor, path: "text", code: "assistant", severity: "warning", required: false, params: {}, ...extra }) as AnalysisIssue;

let editor: Editor | null = null;
afterEach(() => editor?.destroy());

function makeEditor(onOpen = vi.fn()) {
  editor = new Editor({
    extensions: [StarterKit, AssistantHighlights.configure({ onOpen })],
    content: "<p>Strength</p><p>21-15-9 thrustrs and pull-ups</p>",
  });
  return editor;
}

describe("assistant highlights (ADR-181)", () => {
  it("colours issues by kind and skips those without words", () => {
    expect(markCategory(issue("a", "x", { severity: "error" }))).toBe("error");
    expect(markCategory(issue("b", "x", { code: "text_correction" }))).toBe("correction");
    expect(markCategory(issue("c", "x", { code: "assumption", path: "sections.0.timer_config", severity: "info" }))).toBe(
      "assumption",
    );
    expect(markCategory(issue("d", "x", { path: "sections.0.name" }))).toBe("advice");
    expect(anchoredIssues([issue("e", null), issue("f", " ")])).toEqual([]);
  });

  it("finds each issue's words and every mark under a click, overlaps included", () => {
    const { state } = makeEditor();
    const marks = locateMarks(state.doc, [
      { id: "typo", anchor: "thrustrs", category: "correction" },
      { id: "line", anchor: "21-15-9 thrustrs", category: "advice" },
      { id: "gone", anchor: "burpees", category: "error" },
    ]);
    expect(marks.map((mark) => mark.id)).toEqual(["typo", "line"]);
    const typo = marks[0]!;
    expect(state.doc.textBetween(typo.from, typo.to)).toBe("thrustrs");
    expect(marksAt(marks, typo.from + 2).map((mark) => mark.id)).toEqual(["typo", "line"]);
    expect(marksAt(marks, marks[1]!.from + 1).map((mark) => mark.id)).toEqual(["line"]);
  });

  it("marks the words, follows edits and reports clicks", () => {
    const onOpen = vi.fn();
    const current = makeEditor(onOpen);
    current.view.dispatch(
      current.state.tr.setMeta(assistantHighlightsKey, anchoredIssues([issue("typo", "thrustrs", { code: "text_correction" })])),
    );
    expect(current.view.dom.querySelector(".assistant-mark-correction")?.textContent).toBe("thrustrs");

    const mark = assistantHighlightsKey.getState(current.state)!.marks[0]!;
    current.view.someProp("handleClick", (handle) => handle(current.view, mark.from + 1, new MouseEvent("click")));
    expect(onOpen).toHaveBeenCalledWith({ ids: ["typo"], from: mark.from, to: mark.to });

    current.commands.setContent("<p>21-15-9 thrusters</p>");
    expect(current.view.dom.querySelector(".assistant-mark")).toBeNull();
  });
});
