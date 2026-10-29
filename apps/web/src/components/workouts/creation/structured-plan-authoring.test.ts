import { createTranslator } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../../messages/el.json";
import type { Translate } from "@/components/workouts/plan-view/plan-model";
import { backSquat, differentRounds, restSection, section, row } from "@/components/workouts/plan-view/plan-fixtures";

import {
  freeTextPayload,
  planDocumentFrom,
  planHasContent,
  planIsEmpty,
  planPayload,
  planProblems,
  planToText,
  textOfWorkout,
} from "./structured-plan-authoring";

const greek = createTranslator({ locale: "el", messages: el, namespace: "PlanView" }) as unknown as Translate;

describe("loading a workout into the plan editor", () => {
  it("opens a plan workout as written, its draft first", () => {
    const published = backSquat();
    const drafted = differentRounds();
    const doc = planDocumentFrom({
      authoring_mode: "structured_plan",
      title: "Δευτέρα",
      workout_metadata: { plan_note: "Ζέσταμα πρώτα" },
      sections: [{ id: "s1", name: "Old", plan: published }],
      draft_data: { sections: [{ id: "s1", name: "A", plan: drafted, section_metadata: { untitled: true } }, { id: "s2", name: "Β", plan: published }] },
    });
    expect(doc.title).toBe("Δευτέρα");
    expect(doc.note).toBe("Ζέσταμα πρώτα");
    expect(doc.sections.map((s) => [s.id, s.name, s.plan.flow])).toEqual([
      ["s1", "", "for_time"],
      ["s2", "Β", "sets"],
    ]);
  });

  it("starts an empty plan from a text workout, keeping the text as the first section's note", () => {
    const doc = planDocumentFrom({ authoring_mode: "free_text", title: "T", free_text_body: "  AMRAP 12\n10 burpees  " });
    expect(doc.sections).toHaveLength(1);
    expect(doc.sections[0]!.plan).toMatchObject({ v: 1, flow: "sets", note: "AMRAP 12\n10 burpees" });
    expect(doc.sections[0]!.plan.blocks.flat().every((r) => !r.name)).toBe(true);
    expect(planDocumentFrom({ authoring_mode: "free_text", title: "T", free_text_body: "  " }).sections).toEqual([]);
  });

  it("reads text sections as one text", () => {
    const workout = {
      authoring_mode: "sectioned_text",
      title: "T",
      sections: [
        { name: "Strength", free_text_body: "5x5 squat" },
        { name: "", free_text_body: "Run 1k", section_metadata: { untitled: true } },
      ],
    };
    expect(textOfWorkout(workout)).toBe("Strength\n5x5 squat\n\nRun 1k");
    expect(planDocumentFrom(workout).sections[0]!.plan.note).toBe("Strength\n5x5 squat\n\nRun 1k");
  });
});

describe("saving a plan", () => {
  it("sends each section's plan and no exercises, as structured_plan", () => {
    const plan = backSquat();
    const payload = planPayload(
      { title: "Δευτέρα", note: "Ζέσταμα", sections: [{ id: "s1", name: "  ", plan }, { id: "s2", name: "Finisher", plan: restSection() }] },
      "strength",
      { other: true },
    );
    expect(payload).toMatchObject({
      title: "Δευτέρα",
      type: "strength",
      authoring_mode: "structured_plan",
      workout_metadata: { other: true, plan_note: "Ζέσταμα" },
    });
    expect(payload.sections).toEqual([
      { name: "A", order: 1, plan, section_metadata: { untitled: true } },
      { name: "Finisher", order: 2, plan: restSection(), section_metadata: {} },
    ]);
    expect(payload.sections.some((s) => "exercises" in s)).toBe(false);
    expect(payload.draft_data).toEqual({
      title: payload.title,
      type: payload.type,
      authoring_mode: payload.authoring_mode,
      workout_metadata: payload.workout_metadata,
      sections: payload.sections,
    });
    expect(planPayload({ title: "", note: "", sections: [] }, "", { plan_note: "old" }).workout_metadata).toEqual({});
  });

  it("knows when a plan holds something and what blocks publishing", () => {
    const empty = { id: "e", name: "", plan: section("sets", { sets: "4" }, [[row("")]]) };
    expect(planHasContent({ note: "", sections: [empty] })).toBe(false);
    expect(planHasContent({ note: "x", sections: [] })).toBe(true);
    expect(planHasContent({ note: "", sections: [{ ...empty, name: "A" }] })).toBe(true);
    expect(planHasContent({ note: "", sections: [{ id: "b", name: "", plan: backSquat() }] })).toBe(true);
    expect(planIsEmpty([empty])).toBe(true);
    expect(planIsEmpty([{ id: "r", name: "", plan: restSection() }])).toBe(false);
    const bad = section("sets", { sets: "4" }, [[row("Squat", { cells: [{ d: "5", l: "60" }] })]]);
    expect(planProblems([{ id: "ok", name: "", plan: backSquat() }, { id: "bad", name: "", plan: bad }]).map((p) => p.section)).toEqual([2]);
  });
});

describe("switching a plan back to free text", () => {
  it("writes the plan out as text and saves it as a free-text draft", () => {
    const text = planToText({ note: "Ζέσταμα", sections: [{ id: "s1", name: "Δευτέρα A", plan: backSquat() }] }, greek);
    expect(text).toBe(
      ["Ζέσταμα", "", "Δευτέρα A · Σετ", "4 σετ · 2′ ξεκούραση", "Back Squat 12-10-8-8 @ 60-65-70-75% · Tempo ↓3 ·1 ↑X ·1", "  Έλεγχος στο κατέβασμα, με ζώνη"].join("\n"),
    );
    const payload = freeTextPayload("T", "", text, { plan_note: "Ζέσταμα", keep: 1 });
    expect(payload).toMatchObject({ authoring_mode: "free_text", free_text_body: text, type: null, workout_metadata: { keep: 1 } });
    expect(payload.free_text_document).toMatchObject({ type: "doc" });
    expect(payload.draft_data).toMatchObject({ authoring_mode: "free_text", free_text_body: text, free_text_review: null });
  });
});
