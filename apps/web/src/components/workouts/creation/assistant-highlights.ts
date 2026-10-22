import { Extension } from "@tiptap/core";
import type { Node as ProseMirrorNode } from "@tiptap/pm/model";
import { Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";

import type { AnalysisIssue } from "@/lib/free-text-analysis";
import { isAssumptionIssue, isTextCorrection } from "@/lib/free-text-analysis";

/**
 * In-place assistant suggestions (ADR-181): the words an open issue is about
 * (its `anchor`) are underlined in the editor, coloured by kind, like a
 * spell checker. Clicking marked words opens every issue whose words were
 * clicked, right above them. Marks follow the text as it is edited: they are
 * found again on each change and disappear once the words are gone.
 */

export type MarkCategory = "error" | "correction" | "assumption" | "advice";

export const MARK_CATEGORIES: MarkCategory[] = ["error", "correction", "assumption", "advice"];

export function markCategory(issue: AnalysisIssue): MarkCategory {
  if (issue.severity === "error") return "error";
  if (isTextCorrection(issue)) return "correction";
  if (isAssumptionIssue(issue)) return "assumption";
  return "advice";
}

export type AnchoredIssue = { id: string; anchor: string; category: MarkCategory };
export type MarkRange = AnchoredIssue & { from: number; to: number };
export type MarkClick = { ids: string[]; from: number; to: number };

export function anchoredIssues(issues: AnalysisIssue[]): AnchoredIssue[] {
  return issues.flatMap((issue) => {
    const anchor = (issue as AnalysisIssue & { anchor?: string | null }).anchor;
    return typeof anchor === "string" && anchor.trim()
      ? [{ id: issue.id, anchor, category: markCategory(issue) }]
      : [];
  });
}

/**
 * Where each issue's words are in the document: the first place they occur
 * within one block (as the assistant read the text top to bottom).
 */
export function locateMarks(doc: ProseMirrorNode, issues: AnchoredIssue[]): MarkRange[] {
  if (issues.length === 0) return [];
  const blocks: { text: string; positions: number[] }[] = [];
  doc.descendants((node, pos) => {
    if (!node.isTextblock) return true;
    let text = "";
    const positions: number[] = [];
    node.forEach((child, offset) => {
      const start = pos + 1 + offset;
      if (child.isText) {
        for (let index = 0; index < child.text!.length; index += 1) positions.push(start + index);
        text += child.text;
      } else {
        // A hard break reads as a line break, like the text the assistant saw.
        positions.push(start);
        text += "\n";
      }
    });
    blocks.push({ text, positions });
    return false;
  });

  return issues.flatMap((issue) => {
    for (const block of blocks) {
      const at = block.text.indexOf(issue.anchor);
      if (at < 0) continue;
      const from = block.positions[at]!;
      const to = block.positions[at + issue.anchor.length - 1]! + 1;
      return [{ ...issue, from, to }];
    }
    return [];
  });
}

/** The marks a click at `pos` falls in (overlapping marks all count). */
export function marksAt(marks: MarkRange[], pos: number): MarkRange[] {
  return marks.filter((mark) => pos >= mark.from && pos <= mark.to);
}

type PluginState = { issues: AnchoredIssue[]; marks: MarkRange[]; decorations: DecorationSet };

export const assistantHighlightsKey = new PluginKey<PluginState>("assistantHighlights");

function build(doc: ProseMirrorNode, issues: AnchoredIssue[]): PluginState {
  const marks = locateMarks(doc, issues);
  return {
    issues,
    marks,
    decorations: DecorationSet.create(
      doc,
      marks.map((mark) =>
        Decoration.inline(mark.from, mark.to, {
          class: `assistant-mark assistant-mark-${mark.category}`,
          "data-issue-id": mark.id,
        }),
      ),
    ),
  };
}

export type AssistantHighlightsOptions = {
  /** Called with the issues under a click on marked words. */
  onOpen: (click: MarkClick) => void;
};

export const AssistantHighlights = Extension.create<AssistantHighlightsOptions>({
  name: "assistantHighlights",

  addOptions() {
    return { onOpen: () => undefined };
  },

  addProseMirrorPlugins() {
    const options = this.options;
    return [
      new Plugin<PluginState>({
        key: assistantHighlightsKey,
        state: {
          init: (_config, state) => build(state.doc, []),
          apply: (tr, current, _old, state) => {
            const issues = tr.getMeta(assistantHighlightsKey) as AnchoredIssue[] | undefined;
            if (issues) return build(state.doc, issues);
            return tr.docChanged ? build(state.doc, current.issues) : current;
          },
        },
        props: {
          decorations: (state) => assistantHighlightsKey.getState(state)?.decorations,
          handleClick: (view, pos) => {
            const marks = marksAt(assistantHighlightsKey.getState(view.state)?.marks ?? [], pos);
            if (marks.length === 0) return false;
            options.onOpen({
              ids: marks.map((mark) => mark.id),
              from: Math.min(...marks.map((mark) => mark.from)),
              to: Math.max(...marks.map((mark) => mark.to)),
            });
            return false;
          },
        },
      }),
    ];
  },
});
