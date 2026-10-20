import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";

import {
  PENDING_REFERRAL_KEY,
  claimBody,
  claimSettled,
  codeKey,
  forgetReferral,
  inviteChannel,
  markReferralNewAccount,
  readPendingReferrals,
  rememberReferral,
} from "./referral-claim";

const EVENT = "2b0f8f8e-3f7c-4bd4-9b0e-6a4c1d7e9a10";
const day = (n: number) => new Date(Date.UTC(2026, 9, 20 + n));

describe("a friend's kept invites", () => {
  beforeEach(() => window.localStorage.clear());
  afterEach(() => vi.restoreAllMocks());

  it("reads how the link arrived", () => {
    expect(inviteChannel({})).toEqual({ channel: "link", event_id: null });
    expect(inviteChannel({ via: "qr" })).toEqual({ channel: "qr", event_id: null });
    expect(inviteChannel({ event: EVENT, via: "qr" })).toEqual({ channel: "event", event_id: EVENT });
    expect(inviteChannel({ event: "not-an-id" })).toEqual({ channel: "link", event_id: null });
  });

  it("keeps each code once, oldest first, and adds an event to it", () => {
    rememberReferral({ code: "AB12CD34", channel: "link", event_id: null }, day(0));
    rememberReferral({ code: "ZZ99YY88", channel: "qr", event_id: null }, day(1));
    rememberReferral({ code: "ab12-cd34", channel: "event", event_id: EVENT }, day(2));

    const kept = readPendingReferrals(day(3));
    expect(kept.map((entry) => entry.code)).toEqual(["AB12CD34", "ZZ99YY88"]);
    expect(kept[0]).toMatchObject({ channel: "event", event_id: EVENT, saved_at: day(0).toISOString() });
  });

  it("forgets an invite after 60 days", () => {
    rememberReferral({ code: "AB12CD34", channel: "link", event_id: null }, day(0));
    expect(readPendingReferrals(day(60))).toHaveLength(1);
    expect(readPendingReferrals(day(61))).toEqual([]);
    expect(window.localStorage.getItem(PENDING_REFERRAL_KEY)).toBeNull();
  });

  it("drops what it can't read", () => {
    window.localStorage.setItem(
      PENDING_REFERRAL_KEY,
      JSON.stringify([{ code: "AB12CD34", channel: "fax", saved_at: day(0).toISOString() }, "junk", { code: "OK11OK11", channel: "link", saved_at: day(0).toISOString() }]),
    );
    expect(readPendingReferrals(day(1)).map((entry) => entry.code)).toEqual(["OK11OK11"]);
    window.localStorage.setItem(PENDING_REFERRAL_KEY, "{not json");
    expect(readPendingReferrals(day(1))).toEqual([]);
  });

  it("marks a new account and takes the mark back", () => {
    rememberReferral({ code: "AB12CD34", channel: "link", event_id: null });
    markReferralNewAccount();
    expect(readPendingReferrals()[0].new_account).toBe(true);
    markReferralNewAccount(false);
    expect(readPendingReferrals()[0].new_account).toBe(false);
  });

  it("forgets one code, however it is written", () => {
    rememberReferral({ code: "AB12CD34", channel: "link", event_id: null });
    rememberReferral({ code: "ZZ99YY88", channel: "link", event_id: null });
    forgetReferral("ab12 cd34");
    expect(readPendingReferrals().map((entry) => entry.code)).toEqual(["ZZ99YY88"]);
    expect(codeKey("ab-12_cd 34")).toBe("AB12CD34");
  });

  it("sends only what the claim needs", () => {
    expect(claimBody({ code: "AB12CD34", channel: "link", event_id: null, new_account: false })).toEqual({ code: "AB12CD34", channel: "link" });
    expect(claimBody({ code: "AB12CD34", channel: "event", event_id: EVENT, new_account: true })).toEqual({
      code: "AB12CD34",
      channel: "event",
      event_id: EVENT,
      new_account: true,
    });
  });

  it("settles on an answer, retries after a failure", () => {
    expect(claimSettled(new ApiError(404, "gone", { code: "not_found", error: "gone" }))).toBe(true);
    expect(claimSettled(new ApiError(503, "down", { code: "x", error: "down" }))).toBe(false);
    expect(claimSettled(new TypeError("Failed to fetch"))).toBe(false);
  });
});
