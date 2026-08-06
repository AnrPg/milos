import { describe, expect, it } from "vitest";

import { adminHref, pathActive, tenantBrandName } from "@/components/TopNav";

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

  it("matches organization-scoped paths against bare admin hrefs", () => {
    expect(pathActive("/org/atlas-gym/admin/users/123", "/admin/users")).toBe(true);
    expect(pathActive("/org/atlas-gym/admin/finance", "/admin/users")).toBe(false);
  });
});

describe("adminHref", () => {
  it("prefixes admin links with the resolved organization slug", () => {
    expect(adminHref("/admin/users", "atlas-gym")).toBe("/org/atlas-gym/admin/users");
    expect(adminHref("/admin", "atlas-gym")).toBe("/org/atlas-gym/admin");
  });

  it("leaves home unprefixed and falls back to the bare href without a slug", () => {
    expect(adminHref("/", "atlas-gym")).toBe("/");
    expect(adminHref("/admin/users", null)).toBe("/admin/users");
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
