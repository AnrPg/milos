import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import {
  classesCoachedToday,
  coachOptions,
  roleErrorKey,
  staffHomeLayout,
  takeableAthletes,
} from "@/components/admin/staff-home";

describe("staffHomeLayout", () => {
  it("waits for the membership", () => {
    expect(staffHomeLayout(null)).toEqual({ kind: "loading" });
  });

  it("gives owners and admins the dashboard, noting a coach role", () => {
    expect(staffHomeLayout({ role: "admin", roles: ["admin"], capabilities: { grant_staff_roles: "all" } })).toEqual({
      kind: "admin",
      coach: false,
    });
    expect(
      staffHomeLayout({ role: "owner", roles: ["owner", "coach"], capabilities: { grant_staff_roles: "all" } }),
    ).toEqual({ kind: "admin", coach: true });
  });

  it("gives a janitor only the cleaning log", () => {
    expect(
      staffHomeLayout({ role: "janitor", roles: ["janitor", "member"], capabilities: { record_cleaning: "own", report_inventory: "all" } }),
    ).toEqual({ kind: "cleaning" });
  });

  it("composes sections by role union, staff sections in a fixed order", () => {
    expect(
      staffHomeLayout({
        role: "accountant",
        roles: ["accountant", "coach", "janitor"],
        capabilities: { manage_coaching: "own", take_payments: "all", record_cleaning: "own" },
      }),
    ).toEqual({ kind: "sections", sections: ["coach", "accountant", "cleaning"] });
    expect(staffHomeLayout({ role: "front_desk", capabilities: { check_in: "all" } })).toEqual({
      kind: "sections",
      sections: ["front_desk"],
    });
  });
});

describe("roleErrorKey", () => {
  it("maps role error codes and ignores others", () => {
    expect(roleErrorKey(new ApiError(422, "x", { code: "only_athletes_self_assigned" }))).toBe("rhErrOnlyAthletes");
    expect(roleErrorKey(new ApiError(422, "x", { code: "something_else" }))).toBeNull();
    expect(roleErrorKey(new Error("x"))).toBeNull();
  });
});

describe("coachOptions", () => {
  it("keeps coaches sorted by nickname", () => {
    const staff = [
      { user_id: "1", role: "coach", nickname: "Zoe" },
      { user_id: "2", role: "admin", nickname: "Al" },
      { user_id: "3", role: "coach", nickname: "Ann" },
    ];
    expect(coachOptions(staff).map((member) => member.user_id)).toEqual(["3", "1"]);
  });
});

describe("takeableAthletes", () => {
  it("drops athletes who are already clients", () => {
    expect(takeableAthletes([{ id: "a" }, { id: "b" }], ["a"])).toEqual([{ id: "b" }]);
  });
});

describe("classesCoachedToday", () => {
  it("keeps today's classes of this coach, earliest first", () => {
    const now = new Date(2026, 9, 12, 8, 0);
    const at = (hour: number, day = 12) => new Date(2026, 9, day, hour, 0).toISOString();
    const slots = [
      { id: "late", scheduled_at: at(18), coach_user_id: "me" },
      { id: "early", scheduled_at: at(7), coach_user_id: "me" },
      { id: "other", scheduled_at: at(9), coach_user_id: "you" },
      { id: "tomorrow", scheduled_at: at(9, 13), coach_user_id: "me" },
    ];
    expect(classesCoachedToday(slots, "me", now).map((slot) => slot.id)).toEqual(["early", "late"]);
    expect(classesCoachedToday(slots, null, now)).toEqual([]);
  });
});
