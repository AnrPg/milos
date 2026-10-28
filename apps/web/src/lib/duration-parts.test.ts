import { describe, expect, it } from "vitest";
import { formatMinutes, joinMinutes, splitMinutes } from "./duration-parts";

describe("duration parts (ADR-222)", () => {
  it("splits stored minutes into hours and minutes", () => {
    expect(splitMinutes(0)).toEqual({ hours: 0, minutes: 0 });
    expect(splitMinutes(90)).toEqual({ hours: 1, minutes: 30 });
    expect(splitMinutes(720)).toEqual({ hours: 12, minutes: 0 });
  });

  it("joins hours and minutes into one value inside the allowed range", () => {
    expect(joinMinutes({ hours: 2, minutes: 15 }, 0, 10080)).toBe(135);
    expect(joinMinutes({ hours: 0, minutes: 0 }, 1, 10080)).toBe(1);
    expect(joinMinutes({ hours: 168, minutes: 30 }, 0, 10080)).toBe(10080);
  });

  it("round-trips every value", () => {
    for (const total of [0, 1, 59, 60, 61, 1439, 10080]) {
      expect(joinMinutes(splitMinutes(total), 0, 10080)).toBe(total);
    }
  });

  it("reads as words in the viewer's language", () => {
    expect(formatMinutes(90, "en")).toBe("1 hour 30 minutes");
    expect(formatMinutes(60, "en")).toBe("1 hour");
    expect(formatMinutes(1500, "en")).toBe("1 day 1 hour");
    expect(formatMinutes(45, "el")).toBe("45 λεπτά");
  });
});
