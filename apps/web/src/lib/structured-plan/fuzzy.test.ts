import { describe, expect, it } from "vitest";
import { editDistance, fold, fuzzy, rankItems } from "./fuzzy";

describe("fuzzy (ADR-270)", () => {
  it("folds case and Greek accents", () => {
    expect(fold(" Ξεκούραση ")).toBe("ξεκουραση");
    expect(fold("ΑΝΆ ΠΛΕΥΡΆ")).toBe("ανα πλευρα");
    expect(fold("Ροής")).toBe("ροησ");
  });

  it("counts typos with transpositions", () => {
    expect(editDistance("squat", "sqaut")).toBe(1);
    expect(editDistance("emom", "emom")).toBe(0);
    expect(editDistance("abc", "")).toBe(3);
  });

  it("prefers a prefix, then inside a word, then a typo", () => {
    const prefix = fuzzy("squ", "Back Squat");
    const inside = fuzzy("qua", "Back Squat");
    const typo = fuzzy("sqaut", "Back Squat");
    expect(prefix?.score).toBe(10);
    expect(inside?.score).toBe(6);
    expect(typo?.score).toBe(3);
    expect(fuzzy("squat", "Back Squat")?.score).toBe(13);
  });

  it("marks the matched letters in the original text", () => {
    expect(fuzzy("squ", "Back Squat")?.marks).toEqual([[5, 8]]);
    expect(fuzzy("ξεκ", "Ξεκούραση")?.marks).toEqual([[0, 3]]);
    // accents inside the match keep the original indexes
    expect(fuzzy("ξεκουρ", "Ξεκούραση")?.marks).toEqual([[0, 6]]);
  });

  it("is accent and case insensitive in Greek", () => {
    expect(fuzzy("ξεκουραση", "Ξεκούραση")).not.toBeNull();
    expect(fuzzy("ΣΕΤ", "σετ")).not.toBeNull();
    expect(fuzzy("πλευρά", "ανα πλευρα")).not.toBeNull();
  });

  it("allows one typo, two from seven letters, none below three", () => {
    expect(fuzzy("tabta", "Tabata")).not.toBeNull();
    expect(fuzzy("deadlfit", "Deadlift")).not.toBeNull();
    expect(fuzzy("intrevlas", "Intervals")).not.toBeNull();
    expect(fuzzy("xyzzy", "Tabata")).toBeNull();
    expect(fuzzy("tb", "Tabata")).toBeNull();
  });

  it("finds a subsequence of words and needs every query word to match", () => {
    expect(fuzzy("pow sna", "Power Snatch")).not.toBeNull();
    expect(fuzzy("power clean", "Power Snatch")).toBeNull();
    expect(fuzzy("", "anything")).toEqual({ score: 0, marks: [] });
  });

  it("ranks items, label over alias, with a bonus and stable ties", () => {
    const items = [
      { label: "Death by", alt: "emom θανατος" },
      { label: "EMOM", alt: "every minute κάθε λεπτό", bonus: 1 },
      { label: "AMRAP", alt: "as many rounds" },
    ];
    const r = rankItems("emom", items, (x) => x);
    expect(r.map((x) => x.item.label)).toEqual(["EMOM", "Death by"]);
    expect(r[0]).toMatchObject({ onLabel: true, score: 14 });
    expect(r[1]).toMatchObject({ onLabel: false, score: 12 });
    expect(rankItems("", items, (x) => x).map((x) => x.item.label)).toEqual(["Death by", "EMOM", "AMRAP"]);
    expect(rankItems("λεπτο", items, (x) => x)[0].item.label).toBe("EMOM");
  });
});
