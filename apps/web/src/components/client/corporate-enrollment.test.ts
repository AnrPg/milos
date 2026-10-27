import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";

import { companyCodeFromSearch, companyEnrollmentLink, needsEmailConfirmation } from "./corporate-enrollment";

describe("company enrollment links", () => {
  it("reads the code from the link", () => {
    expect(companyCodeFromSearch("?company_code=ryw tye9g".replace(" ", ""))).toBe("RYWTYE9G");
    expect(companyCodeFromSearch("?company_code=%20")).toBeNull();
    expect(companyCodeFromSearch("")).toBeNull();
  });

  it("round-trips the link admins share", () => {
    const link = companyEnrollmentLink("https://gym.example", "AB12CD34");
    expect(link).toBe("https://gym.example/account/billing?company_code=AB12CD34");
    expect(companyCodeFromSearch(new URL(link).search)).toBe("AB12CD34");
  });
});

describe("confirming the email before an email-domain seat (ADR-205)", () => {
  const unverified = new ApiError(403, "Confirm", { code: "corporate_email_unverified", error: "Confirm" });

  it("asks for confirmation when the offer says so", () => {
    expect(needsEmailConfirmation(null, { company_name: "Acme", needs_verification: true }, null)).toBe(true);
    expect(needsEmailConfirmation(null, { company_name: "Acme", needs_verification: false }, null)).toBe(false);
    expect(needsEmailConfirmation(null, null, null)).toBe(false);
  });

  it("asks for confirmation when joining by domain was refused for it", () => {
    expect(needsEmailConfirmation(null, { company_name: "Acme" }, unverified)).toBe(true);
    expect(needsEmailConfirmation(null, { company_name: "Acme" }, new Error("network"))).toBe(false);
  });

  it("never asks on an enrollment link with a code", () => {
    expect(needsEmailConfirmation("AB12CD34", { company_name: "Acme", needs_verification: true }, unverified)).toBe(false);
  });
});
