import { describe, expect, it } from "vitest";

import { leaveRequest, renewableSubscriptions } from "./membership-leaving";

describe("leaveRequest (ADR-220)", () => {
  const form = { when: "end_of_period" as const, date: "2026-12-05", reason: "  Moved  " };

  it("leaves the day to the API at the end of the paid period", () => {
    expect(leaveRequest(form, "2026-11-01", null)).toEqual({ leaving_on: null, reason: "Moved", commitment_override_reason: null });
  });

  it("sends today or the chosen day, and the commitment override", () => {
    expect(leaveRequest({ ...form, when: "today" }, "2026-11-01", null).leaving_on).toBe("2026-11-01");
    expect(leaveRequest({ ...form, when: "date" }, "2026-11-01", "Relocated").leaving_on).toBe("2026-12-05");
    expect(leaveRequest({ ...form, when: "date", date: "" }, "2026-11-01", null).leaving_on).toBe("2026-11-01");
    expect(leaveRequest({ ...form, reason: " " }, "2026-11-01", "Relocated")).toMatchObject({ reason: null, commitment_override_reason: "Relocated" });
  });
});

describe("renewableSubscriptions", () => {
  it("keeps running packages whose renewal is the member's choice", () => {
    const rows = [
      { id: "a", status: "active", auto_renew: true },
      { id: "b", status: "active", auto_renew: false },
      { id: "c", status: "active", auto_renew: null },
      { id: "d", status: "expired", auto_renew: true },
    ];
    expect(renewableSubscriptions(rows).map((row) => row.id)).toEqual(["a", "b"]);
  });
});
