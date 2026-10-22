import { describe, expect, it } from "vitest";

import {
  describePreset,
  editorSectionsFrom,
  emptySection,
  readTextSections,
  sectionProblems,
  sectionsPayload,
  sectionsToFreeText,
} from "./text-sections";

describe("text sections (ADR-179)", () => {
  it("reads a sectioned workout's sections and ignores other workouts", () => {
    const sections = readTextSections({
      authoring_mode: "sectioned_text",
      sections: [
        { id: "a", name: "Strength", free_text_body: "Squat", timer_preset: { format: "emom", rounds: 5 } },
        { id: "b", name: "2", section_metadata: { untitled: true }, free_text_body: "Run", timer_preset: null },
      ],
    });
    expect(sections).toEqual([
      expect.objectContaining({ id: "a", title: "Strength", body: "Squat", preset: expect.objectContaining({ format: "emom", rounds: 5 }) }),
      expect.objectContaining({ id: "b", title: "", body: "Run", preset: null }),
    ]);
    expect(readTextSections({ authoring_mode: "free_text", sections: [{ name: "x" }] })).toEqual([]);
  });

  it("turns a free text into section 1 with the workout's timer, and back", () => {
    const [section] = editorSectionsFrom(
      { authoring_mode: "free_text", free_text_body: "AMRAP 12\n10 burpees" },
      { format: "amrap", duration_seconds: 720 },
    );
    expect(section).toMatchObject({ title: "", body: "AMRAP 12\n10 burpees", preset: { format: "amrap" } });

    const titled = { ...emptySection(), title: "Warm-up", body: "Row 500 m" };
    const free = sectionsToFreeText([titled, section!]);
    expect(free.body).toBe("Warm-up\nRow 500 m\n\nAMRAP 12\n10 burpees");
    expect(free.document.content?.[0]).toMatchObject({ type: "heading", content: [{ text: "Warm-up" }] });
  });

  it("checks the same publish rules as the API", () => {
    const ready = { ...emptySection(), body: "Run 5k", preset: { format: "untimed" as const } };
    const noTimer = { ...emptySection(), body: "Row" };
    const empty = emptySection();
    expect(sectionProblems([ready, noTimer, empty])).toEqual([
      { section: 2, problem: "timer_required" },
      { section: 3, problem: "text_required" },
      { section: 3, problem: "timer_required" },
    ]);
    expect(sectionsPayload([ready])).toEqual([
      expect.objectContaining({ name: "", order: 1, exercises: [], free_text_body: "Run 5k", timer_preset: { format: "untimed" } }),
    ]);
  });

  it("summarises a timer next to its format name", () => {
    expect(describePreset({ format: "amrap", duration_seconds: 720 }, "AMRAP")).toBe("AMRAP · 12:00");
    expect(describePreset({ format: "emom", interval_seconds: 90, rounds: 8 }, "EMOM")).toBe("EMOM · 8 × 1:30");
    expect(describePreset({ format: "tabata" }, "Tabata")).toBe("Tabata · 8 × 0:20/0:10");
    expect(describePreset({ format: "untimed" }, "Stopwatch")).toBe("Stopwatch");
  });
});
