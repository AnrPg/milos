import { describe, expect, it } from "vitest";

import { pathActive, tenantBrandName } from "@/components/TopNav";

describe("pathActive", () => {
  it("only marks Home active on the root page", () => {
    expect(pathActive("/", "/")).toBe(true);
    expect(pathActive("/admin/coaching-assignments", "/")).toBe(false);
    expect(pathActive("/schedule", "/")).toBe(false);
  });

  it("keeps section links active for their nested pages", () => {
    expect(pathActive("/admin/users/123", "/admin/users")).toBe(true);
    expect(pathActive("/admin/coaching-assignments", "/admin/coaching-assignments")).toBe(true);
  });
});

describe("tenantBrandName", () => {
  it("uses the selected organization's configured brand name before the legal organization name", () => {
    expect(
      tenantBrandName(
        [
          {
            organization: { name: "Milos Training", slug: "milos" },
            settings: { brand_name: "Milos Training" },
          },
          {
            organization: { name: "TestAccount LLC", slug: "test-account" },
            settings: { brand_name: "TestAccount" },
          },
        ],
        "test-account",
      ),
    ).toBe("TestAccount");
  });

  it("falls back to organization name when brand settings are absent", () => {
    expect(
      tenantBrandName([
        {
          organization: { name: "TestAccount", slug: "test-account" },
          settings: null,
        },
      ]),
    ).toBe("TestAccount");
  });

  it("returns null when the user has no tenant memberships", () => {
    expect(tenantBrandName([], null)).toBeNull();
  });
});
