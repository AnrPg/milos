import { describe, expect, it } from "vitest";

import { memberEndsOn, overrideFor, shownStatus, statusTone, type ValueOverride } from "./member-standing";

const override = (fields: Partial<ValueOverride>): ValueOverride => ({
  id: "ov",
  field: "status",
  subject_id: "m-1",
  computed_value: "unpaid",
  value: "active",
  reason: null,
  set_by_name: "Apostolos",
  set_at: "2026-10-29T21:41:00Z",
  ...fields,
});

describe("member standing (ADR-274)", () => {
  it("shows the worked-out status, falling back to the stored one", () => {
    expect(shownStatus({ membership: { status: "active", status_shown: "unpaid" } })).toBe("unpaid");
    expect(shownStatus({ membership: { status: "trial" } })).toBe("trial");
    expect(shownStatus({ membership: null })).toBe("");
  });

  it("colours money owed apart from a healthy status", () => {
    expect(statusTone("active")).toBe("good");
    expect(statusTone("unpaid")).toBe("warn");
    expect(statusTone("overdue")).toBe("bad");
    expect(statusTone("paused")).toBe("off");
    expect(statusTone("something-new")).toBe("off");
  });

  it("finds the override in force, per field and subscription", () => {
    const overrides = [
      override({ id: "old", ended_at: "2026-10-28T10:00:00Z", end_reason: "lapsed" }),
      override({ id: "now" }),
      override({ id: "end", field: "ends_on", subject_id: "sub-1" }),
    ];
    expect(overrideFor(overrides, "status")?.id).toBe("now");
    expect(overrideFor(overrides, "ends_on", "sub-1")?.id).toBe("end");
    expect(overrideFor(overrides, "ends_on", "sub-2")).toBeNull();
    expect(overrideFor(undefined, "status")).toBeNull();
  });

  it("«Λήγει» follows the current period, then the subscription, then the profile", () => {
    expect(
      memberEndsOn({
        active_package_subscription: { ends_on: null, current_period: { ends_on: "2026-11-28", renews: true } },
      }),
    ).toEqual({ date: "2026-11-28", renews: true });
    expect(memberEndsOn({ active_package_subscription: { ends_on: "2026-12-01" } })).toEqual({ date: "2026-12-01", renews: false });
    expect(memberEndsOn({ membership: { expires_on: "2027-01-01T00:00:00Z" } })).toEqual({ date: "2027-01-01", renews: false });
    expect(memberEndsOn({})).toEqual({ date: "", renews: false });
  });
});
