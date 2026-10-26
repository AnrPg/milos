import { describe, expect, it } from "vitest";

import type { ScheduleSlot } from "@/api/schedule";
import { classActionsFor } from "./ClassState";

const base = { id: "s", scheduled_at: "2030-01-01T07:00:00Z" } as ScheduleSlot;

describe("classActionsFor (ADR-200)", () => {
  it("offers pause, cancel and delete on an open class", () => {
    expect(classActionsFor(base)).toEqual(["pause", "cancel", "delete"]);
  });

  it("offers resume instead of pause on a paused class", () => {
    expect(classActionsFor({ ...base, paused_at: "2029-12-30T00:00:00Z" })).toEqual(["resume", "cancel", "delete"]);
  });

  it("offers only restore and delete on a cancelled class", () => {
    expect(classActionsFor({ ...base, cancelled_at: "2029-12-30T00:00:00Z" })).toEqual(["restore", "delete"]);
  });
});
