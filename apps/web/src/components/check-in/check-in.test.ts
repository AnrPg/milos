import { describe, expect, it } from "vitest";

import type { DoorCode, ScanResult } from "@/api/check-in";

import {
  clockOffset,
  countdownLabel,
  DEFAULT_RULES,
  doorFrame,
  doorRefetchDelay,
  memberCodeRefetchDelay,
  modeChangeNeedsConfirm,
  nothingReasonKey,
  parseScannedCode,
  scanBody,
  scanView,
  shouldAutoCheckIn,
  undoSecondsLeft,
  validateRules,
} from "./check-in";

const T0 = Date.parse("2026-10-20T18:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();

/** A batch as the API sends it: 30 s windows, each valid one window either side. */
function batch(count: number, rotation = 30, start = T0): DoorCode[] {
  return Array.from({ length: count }, (_, i) => {
    const from = start + i * rotation * 1000;
    return {
      code: `code-${i}`,
      deep_link: `https://milos.test/c/loc-1/code-${i}`,
      shows_from: iso(from),
      valid_until: iso(from + 2 * rotation * 1000),
    };
  });
}

describe("doorFrame", () => {
  it("shows the code whose window has started and counts down to the next one", () => {
    const frame = doorFrame(batch(4), T0 + 12_000, 30);
    expect(frame.current?.code).toBe("code-0");
    expect(frame.secondsUntilRotation).toBe(18);
    expect(frame.nextChangeInMs).toBe(18_000);
    expect(frame.batchEndsAt).toBe(T0 + 120_000);
  });

  it("rotates through the batch without the network", () => {
    const codes = batch(4);
    expect(doorFrame(codes, T0 + 30_000, 30).current?.code).toBe("code-1");
    expect(doorFrame(codes, T0 + 61_000, 30).current?.code).toBe("code-2");
    // The last code shows for one rotation, with no countdown to a next one.
    const last = doorFrame(codes, T0 + 100_000, 30);
    expect(last.current?.code).toBe("code-3");
    expect(last.secondsUntilRotation).toBe(0);
    expect(last.nextChangeInMs).toBe(20_000);
  });

  it("shows nothing once the batch has run out, or before it starts", () => {
    expect(doorFrame(batch(4), T0 + 120_000, 30).current).toBeNull();
    const early = doorFrame(batch(2), T0 - 5_000, 30);
    expect(early.current).toBeNull();
    expect(early.nextChangeInMs).toBe(5_000);
    expect(doorFrame([], T0, 30)).toEqual({ current: null, secondsUntilRotation: 0, nextChangeInMs: null, batchEndsAt: null });
  });

  it("follows the owner's rotation (15 s and 60 s)", () => {
    expect(doorFrame(batch(8, 15), T0 + 46_000, 15).current?.code).toBe("code-3");
    expect(doorFrame(batch(2, 60), T0 + 59_000, 60).secondsUntilRotation).toBe(1);
  });

  it("orders an unsorted batch", () => {
    const codes = batch(3).reverse();
    expect(doorFrame(codes, T0 + 35_000, 30).current?.code).toBe("code-1");
  });
});

describe("doorRefetchDelay", () => {
  it("fetches the next batch halfway through what is left, at least one rotation early", () => {
    const codes = batch(4);
    expect(doorRefetchDelay(doorFrame(codes, T0, 30).batchEndsAt, T0, 30)).toBe(60_000);
    expect(doorRefetchDelay(doorFrame(codes, T0 + 80_000, 30).batchEndsAt, T0 + 80_000, 30)).toBe(10_000);
    expect(doorRefetchDelay(doorFrame(codes, T0 + 110_000, 30).batchEndsAt, T0 + 110_000, 30)).toBe(1_000);
  });

  it("fetches at once when the batch is gone, and retries every 5 s after a failure", () => {
    const codes = batch(2);
    expect(doorRefetchDelay(doorFrame(codes, T0 + 70_000, 30).batchEndsAt, T0 + 70_000, 30)).toBe(0);
    expect(doorRefetchDelay(doorFrame(codes, T0 + 70_000, 30).batchEndsAt, T0 + 70_000, 30, true)).toBe(5_000);
    expect(doorRefetchDelay(doorFrame(codes, T0 + 55_000, 30).batchEndsAt, T0 + 55_000, 30, true)).toBe(5_000);
    expect(doorRefetchDelay(doorFrame([], T0, 30).batchEndsAt, T0, 30)).toBe(0);
  });
});

describe("clocks", () => {
  it("measures the server's clock against ours", () => {
    expect(clockOffset(iso(T0 + 4_000), T0)).toBe(4_000);
    expect(clockOffset(null, T0)).toBe(0);
    expect(clockOffset("not a date", T0)).toBe(0);
  });

  it("labels the countdown and the undo", () => {
    expect(countdownLabel(18)).toBe("0:18");
    expect(countdownLabel(65.2)).toBe("1:06");
    expect(countdownLabel(-3)).toBe("0:00");
    expect(undoSecondsLeft(iso(T0 + 42_500), T0)).toBe(43);
    expect(undoSecondsLeft(iso(T0 - 1), T0)).toBe(0);
    expect(undoSecondsLeft(undefined, T0)).toBe(0);
  });
});

describe("scanView", () => {
  const base = { box: { organization_id: "org-1", slug: "kypseli", name: "Box" }, location: { id: "loc-1", name: "Κεντρικό" } };
  const result = (extra: Partial<ScanResult>) => ({ ...base, outcome: "nothing", ...extra }) as ScanResult;
  const trial = (classes: number, blocked: string | null = null) => ({
    enabled: true,
    approval: "auto" as const,
    blocked_reason: blocked as never,
    classes: Array.from({ length: classes }, (_, i) => ({ id: `c-${i}`, starts_at: iso(T0) })),
  });

  it("maps every door outcome to its view", () => {
    expect(scanView(result({ outcome: "checked_in" }), "door")).toEqual({ kind: "checked_in" });
    expect(scanView(result({ outcome: "already_checked_in" }), "door")).toEqual({ kind: "already" });
    expect(scanView(result({ outcome: "choose" }), "door")).toEqual({ kind: "choose" });
    expect(scanView(result({ outcome: "nothing", classes: [{ id: "c", starts_at: iso(T0) }] }), "door")).toEqual({ kind: "suggestions" });
    expect(scanView(result({ outcome: "nothing", classes: [] }), "door")).toEqual({ kind: "nothing" });
    expect(scanView(result({ outcome: "visitor", trial: trial(2) }), "door")).toEqual({ kind: "visitor", trial: true });
    expect(scanView(result({ outcome: "visitor", trial: trial(0) }), "door")).toEqual({ kind: "visitor", trial: false });
    expect(scanView(result({ outcome: "visitor", trial: trial(2, "trial_already_used") }), "door")).toEqual({ kind: "visitor", trial: false });
    expect(scanView(result({ outcome: "visitor", trial: null }), "door")).toEqual({ kind: "visitor", trial: false });
  });

  it("keeps the poster to the limited outcomes", () => {
    expect(scanView(result({ outcome: "checked_in" }), "poster")).toEqual({ kind: "checked_in" });
    expect(scanView(result({ outcome: "no_booking", membership: "member" }), "poster")).toEqual({ kind: "poster_member" });
    expect(scanView(result({ outcome: "visitor", trial: trial(2) }), "poster")).toEqual({ kind: "poster_visitor" });
    expect(scanView(result({ outcome: "nothing", classes: [{ id: "c", starts_at: iso(T0) }] }), "poster")).toEqual({ kind: "poster_member" });
  });

  it("keeps NFC tags and the arrival reminder to the limited outcomes too (ADR-173)", () => {
    for (const source of ["nfc", "geofence"] as const) {
      expect(scanView(result({ outcome: "visitor", trial: trial(2) }), source)).toEqual({ kind: "poster_visitor" });
      expect(scanView(result({ outcome: "nothing", classes: [{ id: "c", starts_at: iso(T0) }] }), source)).toEqual({ kind: "poster_member" });
    }
    expect(scanBody("door", "l", "c")).toEqual({ location_id: "l", code: "c" });
    expect(scanBody("poster", "l", "c")).toEqual({ location_id: "l", poster_code: "c" });
    expect(scanBody("nfc", "l", "c")).toEqual({ location_id: "l", nfc_code: "c" });
    expect(scanBody("geofence", "l", "t")).toEqual({ geofence_token: "t" });
  });

  it("explains why there was nothing to check in to", () => {
    expect(nothingReasonKey(null)).toBe("scanNothingNoBooking");
    expect(nothingReasonKey("finance_allowance_exhausted")).toBe("scanNothingNoVisits");
    expect(nothingReasonKey("finance_entitlement_inactive")).toBe("scanNothingInactive");
    expect(nothingReasonKey("finance_membership_frozen")).toBe("scanNothingFrozen");
    expect(nothingReasonKey("finance_channel_not_included")).toBe("scanNothingNoOpenGym");
  });
});

describe("personal codes", () => {
  it("re-fetches a rotating code as it rotates, and a static one never", () => {
    expect(memberCodeRefetchDelay({ mode: "rotating", seconds_until_rotation: 12, rotation_seconds: 30 })).toBe(12_250);
    expect(memberCodeRefetchDelay({ mode: "rotating", seconds_until_rotation: 0, rotation_seconds: 30 })).toBe(1_000);
    expect(memberCodeRefetchDelay({ mode: "rotating", seconds_until_rotation: null, rotation_seconds: null })).toBe(30_250);
    expect(memberCodeRefetchDelay({ mode: "static", seconds_until_rotation: null, rotation_seconds: null })).toBeNull();
  });
});

describe("parseScannedCode", () => {
  it("reads personal codes, rotating, static and Wallet", () => {
    expect(parseScannedCode(" M1abcDEF012_-xyz ")).toEqual({ kind: "member", code: "M1abcDEF012_-xyz" });
    expect(parseScannedCode("S1abcdefghij")).toEqual({ kind: "member", code: "S1abcdefghij" });
    expect(parseScannedCode("W1abcdefghij")).toEqual({ kind: "member", code: "W1abcdefghij" });
  });

  it("recognises a door or poster QR held up by mistake, and rejects the rest", () => {
    expect(parseScannedCode("https://milos.app/c/loc-1/AbCdEf0123456789")).toEqual({ kind: "door" });
    expect(parseScannedCode("https://milos.app/c/loc-1/p/AbCdEf0123456789")).toEqual({ kind: "door" });
    expect(parseScannedCode("https://example.com/menu")).toEqual({ kind: "unknown" });
    expect(parseScannedCode("M1 short")).toEqual({ kind: "unknown" });
    expect(parseScannedCode("")).toEqual({ kind: "unknown" });
  });

  it("checks in by itself only in auto mode, when the API says so, once", () => {
    expect(shouldAutoCheckIn({ can_auto_check_in: true, checked_in: null }, true)).toBe(true);
    expect(shouldAutoCheckIn({ can_auto_check_in: true, checked_in: null }, false)).toBe(false);
    expect(shouldAutoCheckIn({ can_auto_check_in: false, checked_in: null }, true)).toBe(false);
    expect(shouldAutoCheckIn({ can_auto_check_in: true, checked_in: { kind: "class" } }, true)).toBe(false);
  });
});

describe("check-in rules", () => {
  it("accepts the defaults and the edges", () => {
    expect(validateRules(DEFAULT_RULES)).toEqual([]);
    expect(validateRules({ ...DEFAULT_RULES, window_before_minutes: 0, window_after_minutes: 120, door_rotation_seconds: 60 })).toEqual([]);
  });

  it("flags windows outside 0–120 minutes and rotations other than 15, 30 or 60 s", () => {
    expect(validateRules({ ...DEFAULT_RULES, window_before_minutes: 121 })).toEqual(["window_before"]);
    expect(validateRules({ ...DEFAULT_RULES, window_after_minutes: -1 })).toEqual(["window_after"]);
    expect(validateRules({ ...DEFAULT_RULES, window_after_minutes: 1.5 })).toEqual(["window_after"]);
    expect(validateRules({ ...DEFAULT_RULES, door_rotation_seconds: 45 as never })).toEqual(["rotation"]);
  });

  it("asks before going back from static to rotating codes only", () => {
    expect(modeChangeNeedsConfirm("static", "rotating")).toBe(true);
    expect(modeChangeNeedsConfirm("rotating", "static")).toBe(false);
    expect(modeChangeNeedsConfirm("static", "static")).toBe(false);
  });
});
