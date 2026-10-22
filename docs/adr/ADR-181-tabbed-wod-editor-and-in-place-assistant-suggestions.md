# ADR-181: Tabbed WOD editor and in-place assistant suggestions
Date: 2026-10-22
Status: Accepted

## Context
The WOD editor stacked a title banner and four collapsible ribbons above the
text, pushing the text down, especially on phones. The assistant's
suggestions lived only in a side panel, far from the words they were about.

## Decision
1. **Tabs.** The banner is gone. Details, Timer, Goals and Formatting (and
   Details and Goals in the sectioned editor) are one row of tabs
   (`EditorTabs`); one panel opens at a time and pressing the open tab closes
   it. When the full labels do not fit beside the assistant switch and save
   status (narrow screens, long languages), the tabs show their icons only,
   with the label kept as accessible name and tooltip.
2. **Anchors.** Each analysis issue carries `anchor`: the words of the
   coach's text it is about, exactly as written
   (`WorkoutAssistant.IssueAnchor`): the words a text fix replaces, else the
   model's `source_text` quote, else the exercise or section name the path
   points at; nil keeps the issue in the panel only.
3. **Marks.** A TipTap extension (`AssistantHighlights`) underlines each open
   issue's words, wavy and colour-coded by kind (error, spelling and units,
   assumption, suggestion; theme colours only), with a small legend. Marks are
   found again on every edit and vanish when the words change.
4. **In place.** Clicking marked words opens every issue whose words contain
   the click, listed one under the other, in a bubble right above the words
   (below when there is no room), on the popover layer; it uses the same
   issue cards as the panel.

## Rationale
Anchoring on text rather than positions survives edits and needs no
character offsets from the model. Server-side anchors keep the rule in one
place and testable.

## Alternatives Considered
* Character offsets from the model: brittle (models miscount) and stale after
  the first edit.
* Client-only anchoring from paths: works for names but not for quoted
  numbers or phrases.

## Consequences
* The model prompt and contract accept an optional `source_text` on issues
  and assumptions; a quote not found in the text is ignored, never a
  contract violation.
* The side panel stays as the overview and holds issues without anchors.
