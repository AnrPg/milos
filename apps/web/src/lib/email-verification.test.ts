import { describe, expect, it } from "vitest";

import { retryWait, showsVerificationBanner } from "@/lib/email-verification";

const unverified = { email: "jo@example.com", email_verified: false };

describe("showsVerificationBanner", () => {
  it("shows to a signed-in, unverified person on ordinary screens", () => {
    expect(showsVerificationBanner({ pathname: "/", user: unverified, dismissed: false })).toBe(true);
    expect(showsVerificationBanner({ pathname: "/org/demo/admin", user: unverified, dismissed: false })).toBe(true);
    expect(showsVerificationBanner({ pathname: "/platform", user: unverified, dismissed: false })).toBe(true);
  });

  it("stays away when verified, unknown, signed out or hidden for the session", () => {
    expect(showsVerificationBanner({ pathname: "/", user: { ...unverified, email_verified: true }, dismissed: false })).toBe(false);
    expect(showsVerificationBanner({ pathname: "/", user: { email: "jo@example.com" }, dismissed: false })).toBe(false);
    expect(showsVerificationBanner({ pathname: "/", user: null, dismissed: false })).toBe(false);
    expect(showsVerificationBanner({ pathname: "/", user: unverified, dismissed: true })).toBe(false);
  });

  it("keeps focused full-screen flows and auth pages clear", () => {
    for (const pathname of ["/verify-email", "/login", "/workouts/w1/execute", "/class-timer/s1/display", "/b/demo-gym", "/welcome"]) {
      expect(showsVerificationBanner({ pathname, user: unverified, dismissed: false })).toBe(false);
    }
  });
});

describe("retryWait", () => {
  it("names short waits and calls long ones later", () => {
    expect(retryWait(42)).toEqual({ kind: "seconds", seconds: 42 });
    expect(retryWait(86_000)).toEqual({ kind: "later" });
  });
});
