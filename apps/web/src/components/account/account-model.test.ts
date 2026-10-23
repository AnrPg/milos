import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import {
  cleanHandleInput,
  describeAccountError,
  looksLikeHandle,
  profileSlotsLeft,
  recoveryCodesFileName,
  recoveryCodesFileText,
} from "@/components/account/account-model";

function apiError(status: number, payload: Record<string, unknown>) {
  return new ApiError(status, "failed", payload);
}

describe("cleanHandleInput", () => {
  it("drops the @, spaces and capitals", () => {
    expect(cleanHandleInput("  @Anna.Pap ")).toBe("anna.pap");
    expect(cleanHandleInput("@@anna pap")).toBe("annapap");
  });

  it("checks only the length locally", () => {
    expect(looksLikeHandle("ab")).toBe(false);
    expect(looksLikeHandle("abc")).toBe(true);
    expect(looksLikeHandle("a".repeat(31))).toBe(false);
  });
});

describe("profileSlotsLeft", () => {
  it("never goes below zero", () => {
    expect(profileSlotsLeft(1, 3)).toBe(2);
    expect(profileSlotsLeft(3, 3)).toBe(0);
    expect(profileSlotsLeft(4, 3)).toBe(0);
  });
});

describe("describeAccountError", () => {
  it("maps coded errors", () => {
    expect(describeAccountError(apiError(422, { code: "invalid_current_password" }))).toEqual({
      key: "errors.currentPassword",
    });
    expect(describeAccountError(apiError(422, { code: "profile_limit", profile_limit: 3 }))).toEqual({
      key: "errors.profileLimit",
      values: { limit: 3 },
    });
    expect(describeAccountError(apiError(409, { code: "email_in_use" }))).toEqual({ key: "errors.emailInUse" });
  });

  it("turns the handle cooldown into a date", () => {
    const described = describeAccountError(
      apiError(422, { code: "validation_failed", errors: { handle: ["can be changed again on 2026-11-05"] } }),
    );
    expect(described?.key).toBe("errors.handleCooldown");
    expect((described?.values?.date as Date).toISOString().slice(0, 10)).toBe("2026-11-05");
  });

  it("tells a taken handle from a malformed one", () => {
    expect(
      describeAccountError(apiError(422, { errors: { handle: ["has already been taken"] } }))?.key,
    ).toBe("errors.handleTaken");
    expect(
      describeAccountError(
        apiError(422, { errors: { handle: ["must be 3-30 Latin letters, numbers, dots or underscores"] } }),
      )?.key,
    ).toBe("errors.handleInvalid");
  });

  it("covers display name, email and password field errors", () => {
    expect(describeAccountError(apiError(422, { errors: { display_name: ["must be 1-50 characters"] } }))?.key).toBe(
      "errors.displayNameInvalid",
    );
    expect(describeAccountError(apiError(422, { errors: { email: ["must be a valid email address"] } }))?.key).toBe(
      "errors.emailInvalid",
    );
    expect(describeAccountError(apiError(422, { errors: { email: ["has already been taken"] } }))?.key).toBe(
      "errors.emailInUse",
    );
    expect(describeAccountError(apiError(422, { errors: { password: ["should be at least 4"] } }))?.key).toBe(
      "errors.weakPassword",
    );
  });

  it("leaves anything else to the generic error text", () => {
    expect(describeAccountError(new Error("boom"))).toBeNull();
    expect(describeAccountError(apiError(500, {}))).toBeNull();
  });
});

describe("recovery codes file", () => {
  it("lists one code per line between the header and the note", () => {
    const text = recoveryCodesFileText({
      heading: "Codes",
      account: "a@b.c · @anna",
      generatedAt: "Created today",
      note: "Each works once.",
      codes: ["aaaaa-bbbbb", "ccccc-ddddd"],
    });
    expect(text.split("\n")).toEqual([
      "Codes",
      "a@b.c · @anna",
      "Created today",
      "",
      "aaaaa-bbbbb",
      "ccccc-ddddd",
      "",
      "Each works once.",
      "",
    ]);
  });

  it("names the file after the handle and the day", () => {
    const day = new Date("2026-10-23T10:00:00Z");
    expect(recoveryCodesFileName("anna.pap", day)).toBe("palee-recovery-codes-anna.pap-2026-10-23.txt");
    expect(recoveryCodesFileName(null, day)).toBe("palee-recovery-codes-2026-10-23.txt");
  });
});
