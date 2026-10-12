import { describe, expect, it } from "vitest";

import { companyCodeFromSearch, companyEnrollmentLink } from "./corporate-enrollment";

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
