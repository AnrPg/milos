import { describe, expect, it } from "vitest";

import { formFromVoiceDraft } from "./voice-draft";

const now = new Date(2026, 9, 21, 18, 30);

describe("formFromVoiceDraft", () => {
  it("fills the log form from the draft for the member to review", () => {
    const form = formFromVoiceDraft(
      {
        title: "Fran",
        duration_minutes: 12,
        perceived_effort: 8,
        days_ago: 1,
        notes: "Πόνεσαν οι ώμοι",
        exercises: [
          { name: "Thruster", sets: 3, reps: 21, load: 42.5, load_unit: "kg" },
          { name: "Pull-up", sets: 3, reps: 21, load: null, load_unit: null },
          { name: "  ", sets: 1, reps: null, load: null, load_unit: null },
          { name: "Deadlift", sets: null, reps: 5, load: 225, load_unit: "lb" },
        ],
      },
      now,
      "Προπόνηση",
    );

    expect(form.title).toBe("Fran");
    expect(form.performedAt).toBe("2026-10-20T18:30");
    expect(form.durationMinutes).toBe("12");
    expect(form.perceivedEffort).toBe("8");
    expect(form.comment).toBe("Πόνεσαν οι ώμοι");
    expect(form.exercises).toEqual([
      { name: "Thruster", sets: "3", reps: "21", load: "42.5", loadUnit: "kg" },
      { name: "Pull-up", sets: "3", reps: "21", load: "", loadUnit: "kg" },
      { name: "Deadlift", sets: "", reps: "5", load: "225", loadUnit: "lb" },
    ]);
  });

  it("tolerates an empty or partial draft (fallback title, today, no rows)", () => {
    const form = formFromVoiceDraft({ title: null, notes: "Τρέξιμο 5 χλμ" }, now, "Προπόνηση");
    expect(form.title).toBe("Προπόνηση");
    expect(form.performedAt).toBe("2026-10-21T18:30");
    expect(form.comment).toBe("Τρέξιμο 5 χλμ");
    expect(form.exercises).toEqual([]);
    expect(formFromVoiceDraft(null, now, "X").title).toBe("X");
  });
});
