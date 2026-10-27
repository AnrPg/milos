import { describe, expect, it } from "vitest";

import { defaultClassStart, nextOpenStart, startsInPast, todayKey } from "@/components/schedule/slot-time";

const ATHENS = "Europe/Athens";

describe("defaultClassStart", () => {
  it("offers 09:00 on the box's clock while that is still ahead", () => {
    const now = new Date("2026-10-27T04:00:00Z"); // 06:00 in Athens
    expect(defaultClassStart("2026-10-27", ATHENS, now).toISOString()).toBe("2026-10-27T07:00:00.000Z");
    expect(defaultClassStart("2026-10-30", ATHENS, now).toISOString()).toBe("2026-10-30T07:00:00.000Z");
  });

  it("offers the next open half hour once 09:00 has passed (the reported 422)", () => {
    const now = new Date("2026-10-27T12:10:00Z"); // 14:10 in Athens
    expect(defaultClassStart("2026-10-27", ATHENS, now).toISOString()).toBe("2026-10-27T12:30:00.000Z");
  });

  it("moves to the next day when the box's day is over", () => {
    const now = new Date("2026-10-27T21:33:00Z"); // 23:33 in Athens
    expect(defaultClassStart("2026-10-27", ATHENS, now).toISOString()).toBe("2026-10-27T22:00:00.000Z"); // 00:00 on the 28th
  });
});

describe("nextOpenStart", () => {
  it("keeps at least fifteen minutes to fill in the form", () => {
    const now = new Date("2026-10-27T12:20:00Z"); // 14:20 in Athens → 14:35 → 15:00
    expect(nextOpenStart(now, ATHENS).toISOString()).toBe("2026-10-27T13:00:00.000Z");
  });
});

describe("startsInPast", () => {
  it("mirrors the API: a start at or before now is refused", () => {
    const now = new Date("2026-10-27T21:33:00Z");
    expect(startsInPast("2026-10-27T07:00:00.000Z", now)).toBe(true);
    expect(startsInPast("2026-10-27T21:33:00.000Z", now)).toBe(true);
    expect(startsInPast("2026-10-27T22:00:00.000Z", now)).toBe(false);
    expect(startsInPast("not a date", now)).toBe(true);
  });
});

describe("todayKey", () => {
  it("is the box's calendar day, not UTC's", () => {
    expect(todayKey(ATHENS, new Date("2026-10-27T22:30:00Z"))).toBe("2026-10-28");
    expect(todayKey("Etc/UTC", new Date("2026-10-27T22:30:00Z"))).toBe("2026-10-27");
  });
});
