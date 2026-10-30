import { describe, expect, it } from "vitest";

import { clockFormat, formatClock, uses24HourClock, withClock } from "./clock";

const evening = new Date(2026, 9, 29, 18, 30);
const morning = new Date(2026, 9, 29, 6, 0);

describe("clock", () => {
  it("writes Greek on the 24-hour clock, never with π.μ./μ.μ.", () => {
    expect(formatClock(evening, "el")).toBe("18:30");
    expect(formatClock(morning, "el")).toBe("06:00");
    expect(formatClock(morning, "el", { hour: "numeric", minute: "2-digit" })).toBe("06:00");
    expect(formatClock(evening, "el-GR", { timeStyle: "short" })).toBe("18:30");
    const full = formatClock(evening, "el", { dateStyle: "medium", timeStyle: "short" });
    expect(full).toContain("18:30");
    expect(full).not.toMatch(/π\.μ\.|μ\.μ\./);
  });

  it("keeps each other locale's own convention", () => {
    expect(formatClock(evening, "en")).toMatch(/06:30\s?PM/);
    expect(formatClock(evening, "de")).toBe("18:30");
    expect(formatClock(evening, "fr")).toBe("18:30");
  });

  it("changes only options that show hours, and only for Greek", () => {
    const dateOnly = { day: "numeric", month: "short" } as const;
    expect(withClock("el", dateOnly)).toBe(dateOnly);
    const english = { hour: "2-digit", minute: "2-digit" } as const;
    expect(withClock("en", english)).toBe(english);
    expect(withClock("el", { hour: "numeric", hour12: true })).toEqual({ hour: "numeric", hourCycle: "h23" });
    expect(withClock(["el", "en"], { timeStyle: "short" })).toEqual({ timeStyle: "short", hourCycle: "h23" });
  });

  it("recognises Greek by its language subtag", () => {
    expect(uses24HourClock("el")).toBe(true);
    expect(uses24HourClock("el-GR")).toBe(true);
    expect(uses24HourClock("EL_cy")).toBe(true);
    expect(uses24HourClock("en-GB")).toBe(false);
    expect(uses24HourClock("")).toBe(false);
  });

  it("returns an empty string for an invalid moment", () => {
    expect(formatClock("not a date", "el")).toBe("");
  });

  it("builds a reusable formatter", () => {
    expect(clockFormat("el", { hour: "2-digit", minute: "2-digit" }).format(morning)).toBe("06:00");
  });
});
