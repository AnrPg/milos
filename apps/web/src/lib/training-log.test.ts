import { describe, expect, it } from "vitest";

import type { TrainingLogEntry } from "@/api/training-log";
import {
  buildCreatePayload,
  buildUpdatePayload,
  emptyTrainingLogForm,
  formFromEntry,
  sortEntriesNewestFirst,
  toDateTimeLocal,
  validateTrainingLogForm,
  type TrainingLogForm,
} from "@/lib/training-log";

const now = new Date(2026, 9, 12, 12, 0);

function form(overrides: Partial<TrainingLogForm> = {}): TrainingLogForm {
  return { ...emptyTrainingLogForm(new Date(2026, 9, 11, 7, 30)), ...overrides };
}

function entry(overrides: Partial<TrainingLogEntry> = {}): TrainingLogEntry {
  return {
    id: "entry-1",
    source_type: "freeform",
    title: "Beach run",
    performed_at_utc: new Date(2026, 9, 11, 7, 30).toISOString(),
    performed_at_tz: "Europe/Athens",
    duration_seconds: 1800,
    perceived_effort: 6,
    notes: "Windy",
    status: "logged",
    lock_version: 3,
    section_scores: [],
    exercise_modifications: [],
    performed_exercises: [{ name: "Sprint", sets: 6, load: 10, load_unit: "lb" }],
    ...overrides,
  } as TrainingLogEntry;
}

describe("validateTrainingLogForm", () => {
  it("requires a title only for freeform logs", () => {
    expect(validateTrainingLogForm(form(), "freeform", now)).toContain("titleRequired");
    expect(validateTrainingLogForm(form(), "class", now)).toEqual([]);
  });

  it("rejects future performances beyond the tolerance and bad numbers", () => {
    const errors = validateTrainingLogForm(
      form({
        title: "x",
        performedAt: toDateTimeLocal(new Date(2026, 9, 12, 14, 0)),
        durationMinutes: "abc",
        exercises: [{ name: "", sets: "3", reps: "", load: "", loadUnit: "kg" }],
      }),
      "freeform",
      now,
    );

    expect(errors).toEqual(["performedAtFuture", "durationInvalid", "exerciseNameRequired"]);
  });

  it("ignores completely empty exercise rows", () => {
    expect(
      validateTrainingLogForm(
        form({ title: "x", exercises: [{ name: "", sets: "", reps: "", load: "", loadUnit: "kg" }] }),
        "freeform",
        now,
      ),
    ).toEqual([]);
  });
});

describe("buildCreatePayload", () => {
  it("builds a freeform payload with converted units and trimmed rows", () => {
    const payload = buildCreatePayload(
      form({
        title: "  Hotel gym ",
        durationMinutes: "45",
        perceivedEffort: "7",
        notes: "  ",
        exercises: [
          { name: " Squat ", sets: "5", reps: "5", load: "100", loadUnit: "kg" },
          { name: "", sets: "", reps: "", load: "", loadUnit: "kg" },
        ],
      }),
      { sourceType: "freeform", referenceId: "ignored", title: "", scoreableSections: [] },
      { idempotencyKey: "log-key-123", timezone: "Europe/Athens" },
    );

    expect(payload).toMatchObject({
      source_type: "freeform",
      source_reference_id: null,
      title: "Hotel gym",
      duration_seconds: 2700,
      perceived_effort: 7,
      notes: null,
      timezone: "Europe/Athens",
      idempotency_key: "log-key-123",
      section_scores: [],
      performed_exercises: [{ name: "Squat", sets: 5, reps: 5, load: 100, load_unit: "kg" }],
    });
    expect(payload.performed_at).toBe(new Date(2026, 9, 11, 7, 30).toISOString());
  });

  it("sends the source reference and only filled section scores for sourced logs", () => {
    const payload = buildCreatePayload(
      form({ sectionScores: { s1: "300", s2: "", s3: "5+12" } }),
      {
        sourceType: "class",
        referenceId: "slot-1",
        title: "CrossFit",
        scoreableSections: [
          { id: "s1", name: "For time", unit: "seconds", score_type: "time" },
          { id: "s2", name: "Skill", unit: null, score_type: null },
          { id: "s3", name: "AMRAP", unit: "rounds", score_type: "rounds" },
        ],
      },
      { idempotencyKey: "log-key-456", timezone: "UTC" },
    );

    expect(payload.source_reference_id).toBe("slot-1");
    expect(payload.title).toBeNull();
    expect(payload.section_scores).toEqual([
      { section_id: "s1", value: 300, unit: "seconds" },
      { section_id: "s3", value: "5+12", unit: "rounds" },
    ]);
  });
});

describe("editing", () => {
  it("round-trips an entry into the form and back into an update payload", () => {
    const original = entry();
    const editForm = formFromEntry(original);

    expect(editForm).toMatchObject({
      title: "Beach run",
      durationMinutes: "30",
      perceivedEffort: "6",
      notes: "Windy",
      exercises: [{ name: "Sprint", sets: "6", reps: "", load: "10", loadUnit: "lb" }],
    });

    const payload = buildUpdatePayload({ ...editForm, notes: "Calm" }, original, [], "UTC");
    expect(payload).toMatchObject({ title: "Beach run", notes: "Calm", expected_version: 3 });
    expect(payload).not.toHaveProperty("section_scores");
  });

  it("never sends a title for sourced entries", () => {
    const payload = buildUpdatePayload(
      formFromEntry(entry({ source_type: "class" })),
      entry({ source_type: "class" }),
      [],
      "UTC",
    );
    expect(payload).not.toHaveProperty("title");
  });
});

it("sorts entries newest first without mutating the input", () => {
  const older = entry({ id: "older", performed_at_utc: "2026-10-01T10:00:00Z" });
  const newer = entry({ id: "newer", performed_at_utc: "2026-10-10T10:00:00Z" });
  const input = [older, newer];

  expect(sortEntriesNewestFirst(input).map((item) => item.id)).toEqual(["newer", "older"]);
  expect(input[0].id).toBe("older");
});
