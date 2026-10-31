import { describe, expect, it } from "vitest";

import { passFileName, passLines, spacedCode, type PickupPass } from "./pickup-pass";

const pass: PickupPass = {
  code: "K7MQ4X",
  reference: "K-1042",
  box: "Box Κυψέλη",
  place: "Υποδοχή",
  total: "45,00 €",
  labels: { code: "Κωδικός παραλαβής", showAtDesk: "Δείξε το στην υποδοχή" },
};

describe("pickup pass (ADR-291)", () => {
  it("splits the six-character code for reading aloud", () => {
    expect(spacedCode("K7MQ4X")).toBe("K7M Q4X");
    expect(spacedCode("ABC")).toBe("ABC");
  });

  it("lists the order, where, how much and what to do, skipping blanks", () => {
    expect(passLines(pass)).toEqual(["K-1042", "Box Κυψέλη · Υποδοχή", "45,00 €", "Δείξε το στην υποδοχή"]);
    expect(passLines({ ...pass, box: null, place: null })).toEqual(["K-1042", "45,00 €", "Δείξε το στην υποδοχή"]);
  });

  it("names the file after the order and its code", () => {
    expect(passFileName(pass)).toBe("palee-k-1042-k7mq4x.png");
  });
});
