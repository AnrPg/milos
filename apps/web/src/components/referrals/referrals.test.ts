import { describe, expect, it } from "vitest";

import type { ReferralInvite, StaffReferralInvite } from "@/api/referrals";

import { giftText, invitePill, inviteUrl, reachedSteps, rewardText, sortForStaff } from "./referrals";

const t = (key: string, values?: Record<string, string | number>) =>
  values ? `${key}(${Object.entries(values).map(([k, v]) => `${k}=${v}`).join(",")})` : key;

function invite(overrides: Partial<ReferralInvite> = {}): ReferralInvite {
  return {
    id: "a",
    friend: { id: "f", nickname: "Κατερίνα" },
    stage: "signed_up",
    stage_at: "2026-10-20T10:00:00Z",
    status: "open",
    channel: "link",
    attributed_at: "2026-10-20T10:00:00Z",
    expires_at: "2026-12-19T10:00:00Z",
    reward: { type: "credit", value: 2000, status: "upcoming" },
    ...overrides,
  };
}

describe("«Φέρε φίλο» words", () => {
  it("says what the friend gets", () => {
    expect(giftText({ type: "free_days", value: 7 }, t, "el")).toBe("gift.freeDays(days=7)");
    expect(giftText({ type: "credit", value: 2000 }, t, "en")).toBe("gift.credit(amount=€20)");
    expect(giftText({ type: "custom", value: 0, note: " Μπλουζάκι " }, t, "el")).toBe("Μπλουζάκι");
    expect(giftText(null, t, "el")).toBeNull();
  });

  it("says what the member gets", () => {
    expect(rewardText({ type: "credit", value: 2050 }, t, "en")).toBe("reward.credit(amount=€20.50)");
    expect(rewardText({ type: "discount", value: 15 }, t, "el")).toBe("reward.discount(percent=15)");
    expect(rewardText({ type: "free_period", value: 30 }, t, "el")).toBe("reward.freePeriod(days=30)");
    expect(rewardText({ type: "manual", value: 0, note: null }, t, "el")).toBe("reward.manual");
  });

  it("shows the step until there is a reward to show", () => {
    expect(invitePill(invite(), t)).toEqual({ label: "stage.signed_up", tone: "neutral" });
    expect(invitePill(invite({ stage: "trial" }), t)).toEqual({ label: "stage.trial", tone: "accent" });
    expect(invitePill(invite({ stage: "paid", reward: { type: "credit", value: 2000, status: "pending" } }), t)).toEqual({
      label: "rewardStatus.pending",
      tone: "accent",
    });
    expect(invitePill(invite({ reward: { type: "credit", value: 2000, status: "given" } }), t).tone).toBe("ok");
    expect(invitePill(invite({ status: "expired" }), t)).toEqual({ label: "status.expired", tone: "muted" });
  });

  it("builds the links a member shares", () => {
    expect(inviteUrl("https://palee.gr", "AB12CD34")).toBe("https://palee.gr/r/AB12CD34");
    expect(inviteUrl("https://palee.gr", "AB12CD34", { via: "qr" })).toBe("https://palee.gr/r/AB12CD34?via=qr");
    expect(inviteUrl("https://palee.gr", "AB12CD34", { eventId: "e1", via: "qr" })).toBe("https://palee.gr/r/AB12CD34?event=e1");
  });
});

describe("staff's queue", () => {
  const staff = (id: string, at: string, status?: "pending" | "approved"): StaffReferralInvite => ({
    ...invite({ id, attributed_at: at, reward: status ? { type: "credit", value: 2000, status } : null }),
    steps: {},
    new_account: false,
  });

  it("puts invites waiting for approval first, then the newest", () => {
    const sorted = sortForStaff([
      staff("old", "2026-10-01T00:00:00Z"),
      staff("new", "2026-10-19T00:00:00Z"),
      staff("waiting", "2026-09-01T00:00:00Z", "pending"),
    ]);
    expect(sorted.map((entry) => entry.id)).toEqual(["waiting", "new", "old"]);
  });

  it("lists the steps reached in order", () => {
    const steps = reachedSteps({
      attributed_at: "2026-10-01T00:00:00Z",
      steps: { trial_at: "2026-10-05T00:00:00Z", paid_at: "2026-10-09T00:00:00Z" },
    });
    expect(steps.map((step) => step.stage)).toEqual(["signed_up", "trial", "paid"]);
  });
});
