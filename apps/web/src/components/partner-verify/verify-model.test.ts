import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import type { SponsorCandidate, VerificationOverview, VerificationRequest } from "@/api/partner-verification";

import {
  canWithdraw,
  candidateAction,
  cleanCode,
  errorFor,
  formatCountdown,
  plausiblePhone,
  secondsLeft,
  selfieContentType,
  selfieProblem,
  sortCandidates,
  stepItems,
  verifyErrorField,
  verifyErrorKey,
  verifyView,
} from "./verify-model";

const limits: VerificationOverview["limits"] = {
  code_attempts: 5,
  code_minutes: 10,
  link_minutes: 10,
  selfie_content_types: ["image/heic", "image/jpeg", "image/png", "image/webp"],
  selfie_max_bytes: 8 * 1024 * 1024,
  selfie_retention_days: 7,
  sponsors_required: 2,
};

function request(overrides: Partial<VerificationRequest> = {}): VerificationRequest {
  return {
    id: "req-1",
    status: "collecting",
    consent_at: "2026-10-30T10:00:00Z",
    decided_at: null,
    decision_reason: null,
    missing: [],
    phone: null,
    phone_verified: false,
    selfie_code: "4827",
    selfie_expires_at: null,
    selfie_uploaded_at: null,
    sponsors: [],
    sponsors_required: 2,
    submitted_at: null,
    vouches: 0,
    ...overrides,
  };
}

function overview(
  eligibility: VerificationOverview["eligibility"],
  req: VerificationRequest | null = null,
): VerificationOverview {
  return { eligibility, request: req, limits };
}

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });

function candidate(overrides: Partial<SponsorCandidate> & { id: string; nickname: string }): SponsorCandidate {
  const { id, nickname, ...rest } = overrides;
  return { person: person(id, nickname), eligible: true, reason: null, sponsorship: null, ...rest };
}

describe("verifyView", () => {
  it("shows people verified through a membership only that they are verified", () => {
    expect(verifyView(overview({ status: "verified", method: "membership", next_step: null }))).toEqual({
      kind: "verified",
      method: "membership",
    });
  });

  it("maps suspended, in review and rejected to their own screens", () => {
    expect(verifyView(overview({ status: "suspended", method: "sponsors", next_step: null })).kind).toBe("suspended");
    expect(verifyView(overview({ status: "in_review", method: null, next_step: null }, request({ status: "in_review" }))).kind).toBe(
      "in_review",
    );
    expect(
      verifyView(
        overview({ status: "rejected", method: null, next_step: "consent" }, request({ status: "rejected", decision_reason: "Blurry photo" })),
      ),
    ).toEqual({ kind: "rejected", reason: "Blurry photo" });
  });

  it("starts a person without a request at consent, everything else locked", () => {
    const view = verifyView(overview({ status: "needs_verification", method: null, next_step: "consent" }));
    expect(view.kind).toBe("steps");
    if (view.kind !== "steps") return;
    expect(view.steps.map((step) => [step.key, step.state, step.current])).toEqual([
      ["consent", "open", true],
      ["sponsors", "locked", false],
      ["phone", "locked", false],
      ["selfie", "locked", false],
    ]);
  });

  it("flags a request whose selfie expired unchecked", () => {
    const view = verifyView(
      overview({ status: "needs_verification", method: null, next_step: "selfie" }, request({ status: "expired", vouches: 2, phone_verified: true })),
    );
    expect(view.kind === "steps" && view.selfieExpired).toBe(true);
  });
});

describe("stepItems", () => {
  it("opens sponsors and phone together after consent; the selfie waits for both", () => {
    expect(stepItems(request(), "sponsors").map((step) => step.state)).toEqual(["done", "open", "open", "locked"]);
    expect(stepItems(request({ vouches: 2 }), "phone").map((step) => step.state)).toEqual(["done", "done", "open", "locked"]);
    expect(stepItems(request({ phone_verified: true, vouches: 1 }), "sponsors").map((step) => step.state)).toEqual([
      "done",
      "open",
      "done",
      "locked",
    ]);
  });

  it("opens the selfie once two sponsors vouched and the number is confirmed", () => {
    const steps = stepItems(request({ vouches: 2, phone_verified: true }), "selfie");
    expect(steps.map((step) => step.state)).toEqual(["done", "done", "done", "open"]);
    expect(steps.find((step) => step.current)?.key).toBe("selfie");
  });
});

describe("canWithdraw", () => {
  it("allows withdrawing open requests only", () => {
    expect(canWithdraw(null)).toBe(false);
    expect(canWithdraw(request({ status: "collecting" }))).toBe(true);
    expect(canWithdraw(request({ status: "in_review" }))).toBe(true);
    expect(canWithdraw(request({ status: "expired" }))).toBe(true);
    expect(canWithdraw(request({ status: "rejected" }))).toBe(false);
    expect(canWithdraw(request({ status: "withdrawn" }))).toBe(false);
  });
});

describe("sponsor candidates", () => {
  it("offers «Ζήτα» only to eligible Buddies not yet asked, and cancel while unanswered", () => {
    expect(candidateAction(candidate({ id: "a", nickname: "A" }), false)).toBe("ask");
    expect(candidateAction(candidate({ id: "a", nickname: "A", eligible: false, reason: "not_verified" }), false)).toBe("none");
    expect(candidateAction(candidate({ id: "a", nickname: "A", sponsorship: { status: "requested" } }), false)).toBe("cancel");
    expect(candidateAction(candidate({ id: "a", nickname: "A", sponsorship: { status: "vouched" } }), false)).toBe("none");
    expect(candidateAction(candidate({ id: "a", nickname: "A", sponsorship: { status: "declined" } }), false)).toBe("none");
    expect(candidateAction(candidate({ id: "a", nickname: "A", sponsorship: { status: "cancelled" } }), false)).toBe("ask");
  });

  it("asks nobody more once enough vouched, but still lets a pending request be cancelled", () => {
    expect(candidateAction(candidate({ id: "a", nickname: "A" }), true)).toBe("none");
    expect(candidateAction(candidate({ id: "a", nickname: "A", sponsorship: { status: "requested" } }), true)).toBe("cancel");
  });

  it("lists vouched, then asked, then eligible, then declined, then those who cannot vouch", () => {
    const sorted = sortCandidates([
      candidate({ id: "x", nickname: "Xenia", eligible: false, reason: "not_verified" }),
      candidate({ id: "d", nickname: "Dora", sponsorship: { status: "declined" } }),
      candidate({ id: "b", nickname: "Babis" }),
      candidate({ id: "r", nickname: "Rena", sponsorship: { status: "requested" } }),
      candidate({ id: "v", nickname: "Vasso", sponsorship: { status: "vouched" } }),
      candidate({ id: "a", nickname: "Alekos" }),
    ]);
    expect(sorted.map((row) => row.person.id)).toEqual(["v", "r", "a", "b", "d", "x"]);
  });
});

describe("link countdown", () => {
  it("counts whole seconds down to zero and formats m:ss", () => {
    const now = Date.parse("2026-10-30T10:00:00Z");
    expect(secondsLeft("2026-10-30T10:10:00Z", now)).toBe(600);
    expect(secondsLeft("2026-10-30T10:00:00.400Z", now)).toBe(1);
    expect(secondsLeft("2026-10-30T09:59:00Z", now)).toBe(0);
    expect(formatCountdown(600)).toBe("10:00");
    expect(formatCountdown(545)).toBe("9:05");
    expect(formatCountdown(0)).toBe("0:00");
  });
});

describe("phone and code", () => {
  it("keeps six digits of the code", () => {
    expect(cleanCode("12a3 45-678")).toBe("123456");
  });

  it("sends only numbers that look like a phone", () => {
    expect(plausiblePhone("6912345678")).toBe(true);
    expect(plausiblePhone("+30 691 234 5678")).toBe(true);
    expect(plausiblePhone("12345")).toBe(false);
    expect(plausiblePhone("call me")).toBe(false);
  });
});

describe("selfie", () => {
  const accepted = limits.selfie_content_types;

  it("takes the declared type or guesses it from the extension", () => {
    expect(selfieContentType({ type: "image/jpeg", name: "a.jpg" }, accepted)).toBe("image/jpeg");
    expect(selfieContentType({ type: "", name: "IMG_1.HEIC" }, accepted)).toBe("image/heic");
    expect(selfieContentType({ type: "image/heif", name: "x" }, accepted)).toBe("image/heic");
    expect(selfieContentType({ type: "image/gif", name: "a.gif" }, accepted)).toBeNull();
  });

  it("refuses a wrong type or a photo over the limit before uploading", () => {
    expect(selfieProblem({ type: "image/png", name: "a.png", size: 1000 }, accepted, limits.selfie_max_bytes)).toBeNull();
    expect(selfieProblem({ type: "application/pdf", name: "a.pdf", size: 1000 }, accepted, limits.selfie_max_bytes)).toBe("type");
    expect(selfieProblem({ type: "image/png", name: "a.png", size: limits.selfie_max_bytes + 1 }, accepted, limits.selfie_max_bytes)).toBe(
      "size",
    );
  });
});

describe("error mapping", () => {
  const apiError = (code: string, status = 422) => new ApiError(status, code, { code });

  it("puts phone errors under the number and code errors under the code", () => {
    expect(verifyErrorField(apiError("partner_phone_invalid"))).toBe("phone");
    expect(verifyErrorField(apiError("partner_phone_taken", 409))).toBe("phone");
    expect(verifyErrorField(apiError("partner_phone_rate_limited", 429))).toBe("phone");
    expect(verifyErrorField(apiError("sms_unavailable", 503))).toBe("phone");
    expect(verifyErrorField(apiError("partner_code_invalid"))).toBe("code");
    expect(verifyErrorField(apiError("partner_code_expired", 410))).toBe("code");
    expect(verifyErrorField(apiError("partner_selfie_invalid"))).toBe("selfie");
    expect(verifyErrorField(apiError("partner_decision_reason_required"))).toBe("reason");
  });

  it("keeps other errors for the whole step", () => {
    expect(verifyErrorField(apiError("partner_sponsor_quota", 429))).toBe("form");
    expect(verifyErrorField(apiError("something_else"))).toBe("form");
    expect(verifyErrorField(new Error("network"))).toBe("form");
  });

  it("words known codes itself and leaves the rest to the shared wording", () => {
    expect(verifyErrorKey(apiError("partner_link_expired", 410))).toBe("error.partner_link_expired");
    expect(verifyErrorKey(apiError("not_found", 404))).toBeNull();
    expect(verifyErrorKey(null)).toBeNull();
  });

  it("gives a field only its own error", () => {
    const error = apiError("partner_code_invalid");
    expect(errorFor(error, "code")).toBe(error);
    expect(errorFor(error, "phone")).toBeNull();
    expect(errorFor(null, "code")).toBeNull();
  });
});
