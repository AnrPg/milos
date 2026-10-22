import { describe, expect, it } from "vitest";

import {
  addDaysToKey,
  dateKeyInZone,
  dateTimeLocalInZone,
  dateTimeLocalToIso,
  isValidTimeZone,
  offsetMinutes,
  readZoned,
  sameClock,
  startOfDayInZone,
  timeKeyInZone,
  zonedText,
  zonedToInstant,
  zoneLabel,
} from "@/lib/zoned-time";

const at = "2026-10-24T16:00:00Z"; // 19:00 in Athens (EEST), 17:00 in London (BST)

describe("zoned-time", () => {
  it("knows zones and names them by city", () => {
    expect(isValidTimeZone("Europe/Athens")).toBe(true);
    expect(isValidTimeZone("Mars/Olympus")).toBe(false);
    expect(isValidTimeZone(null)).toBe(false);
    expect(zoneLabel("America/Argentina/Buenos_Aires")).toBe("Buenos Aires");
    expect(zoneLabel("Etc/UTC")).toBe("UTC");
  });

  it("reads a moment on a zone's clock", () => {
    expect(offsetMinutes(at, "Europe/Athens")).toBe(180);
    expect(timeKeyInZone(at, "Europe/Athens")).toBe("19:00");
    expect(dateKeyInZone("2026-10-24T22:30:00Z", "Europe/Athens")).toBe("2026-10-25");
    expect(dateTimeLocalInZone(at, "Europe/London")).toBe("2026-10-24T17:00");
  });

  it("compares clocks by offset at that instant", () => {
    expect(sameClock(at, "Europe/Athens", "Europe/Bucharest")).toBe(true);
    expect(sameClock(at, "Europe/Athens", "Europe/London")).toBe(false);
  });

  it("turns a wall-clock time back into the moment", () => {
    expect(zonedToInstant("2026-10-24", "19:00", "Europe/Athens").toISOString()).toBe("2026-10-24T16:00:00.000Z");
    expect(dateTimeLocalToIso("2026-10-24T17:00", "Europe/London")).toBe("2026-10-24T16:00:00.000Z");
    expect(startOfDayInZone("2026-10-24", "Europe/Athens").toISOString()).toBe("2026-10-23T21:00:00.000Z");
  });

  it("handles DST gaps and repeats", () => {
    // 03:30 does not exist in Athens on 29 March 2026 (03:00 -> 04:00).
    expect(timeKeyInZone(zonedToInstant("2026-03-29", "03:30", "Europe/Athens"), "Europe/Athens")).toBe("04:30");
    // 03:30 happens twice on 25 October 2026; the first one is EEST.
    expect(zonedToInstant("2026-10-25", "03:30", "Europe/Athens").toISOString()).toBe("2026-10-25T00:30:00.000Z");
  });

  it("adds the viewer's clock only when it differs", () => {
    const away = readZoned(at, "Europe/Athens", "Europe/London", "en-GB", "time");
    expect(away).toMatchObject({ text: "19:00", zone: "Athens", local: "17:00", localZone: "London" });
    expect(readZoned(at, "Europe/Athens", "Europe/Athens", "en-GB").local).toBeNull();
    expect(zonedText(at, "Europe/Athens", "en-GB", "time", "Europe/London")).toBe("19:00 Athens");
    expect(zonedText(at, "Europe/Athens", "en-GB", "time", "Europe/Athens")).toBe("19:00");
  });

  it("names the viewer's weekday when their day differs", () => {
    const late = readZoned("2026-10-24T20:00:00Z", "Europe/Athens", "Asia/Tokyo", "en-GB", "time");
    expect(late.local).toMatch(/Sun/);
  });

  it("adds days to a key", () => {
    expect(addDaysToKey("2026-10-31", 1)).toBe("2026-11-01");
  });
});
