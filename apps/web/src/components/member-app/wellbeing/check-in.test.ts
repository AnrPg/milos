import { describe, expect, it } from "vitest";

import type { CheckInRecord } from "@/api/wellbeing";

import { draftAnswers, latestAnswers, questionTimeline, toggleAnswer } from "./check-in";

function checkIn(id: string, at: string, answers: CheckInRecord["answers"]): CheckInRecord {
  return {
    id,
    user_id: "u",
    organization_id: null,
    recorded_at: at,
    recorded_tz: "UTC",
    journal_visibility: "private",
    answers,
    inserted_at: at,
    updated_at: at,
  };
}

describe("check-in draft", () => {
  it("selects, switches and clears an answer, keeping its note while switching", () => {
    let draft = toggleAnswer({}, "mood", 2);
    draft = { ...draft, mood: { ...draft.mood, note: "long day" } };
    draft = toggleAnswer(draft, "mood", 3);
    expect(draft).toEqual({ mood: { value: 3, note: "long day" } });
    expect(toggleAnswer(draft, "mood", 3)).toEqual({});
  });

  it("builds answers in catalog order and drops blank notes", () => {
    const draft = { stress: { value: 1 as const, note: " deadline " }, sleep: { value: 4 as const, note: "  " } };
    expect(draftAnswers(draft, ["sleep", "energy", "stress"])).toEqual([
      { question_key: "sleep", value: 4 },
      { question_key: "stress", value: 1, note: "deadline" },
    ]);
  });
});

describe("check-in timeline", () => {
  const checkIns = [
    checkIn("a", "2026-10-16T06:00:00Z", [{ question_key: "energy", value: 1, note: null }]),
    checkIn("b", "2026-10-16T12:00:00Z", [
      { question_key: "energy", value: 4, note: "after coffee" },
      { question_key: "mood", value: 3, note: null },
    ]),
  ];

  it("places a point per submission that answered the question", () => {
    const points = questionTimeline(checkIns, "energy", new Date("2026-10-16T00:00:00Z"), new Date("2026-10-17T00:00:00Z"));
    expect(points.map(({ id, x, y, note }) => ({ id, x, y, note }))).toEqual([
      { id: "a", x: 0.25, y: 0, note: null },
      { id: "b", x: 0.5, y: 1, note: "after coffee" },
    ]);
    expect(questionTimeline(checkIns, "sleep", new Date(0), new Date())).toEqual([]);
  });

  it("takes the latest answer to each question as the current state", () => {
    expect(latestAnswers(checkIns)).toEqual({
      energy: { value: 4, at: "2026-10-16T12:00:00Z" },
      mood: { value: 3, at: "2026-10-16T12:00:00Z" },
    });
  });
});
