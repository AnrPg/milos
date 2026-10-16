import { describe, expect, it } from "vitest";

import { adminHref, pathActive, tenantBrandLogoUrl, tenantBrandName } from "@/components/TopNav";

describe("pathActive", () => {
  it("only marks Home active on the root page", () => {
    expect(pathActive("/", "/")).toBe(true);
    expect(pathActive("/admin/coaching-assignments", "/")).toBe(false);
    expect(pathActive("/box/schedule", "/")).toBe(false);
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

describe("tenantBrandLogoUrl", () => {
  const memberships = [
    {
      organization: { name: "Milos Training", slug: "milos" },
      settings: { brand_logo_url: "https://media.test/organizations/a/branding/logo/a.png" },
    },
    {
      organization: { name: "TestAccount", slug: "test-account" },
      settings: { brand_logo_url: "  " },
    },
  ];

  it("uses the selected organization's logo", () => {
    expect(tenantBrandLogoUrl(memberships, "milos")).toBe(
      "https://media.test/organizations/a/branding/logo/a.png",
    );
  });

  it("does not leak another organization's logo when the selected one has none", () => {
    expect(tenantBrandLogoUrl(memberships, "test-account")).toBeNull();
    expect(tenantBrandLogoUrl([], null)).toBeNull();
  });
});

describe("pathActive for my workouts", () => {
  it("keeps My Workouts inactive on the journal pages that used to sit under it", () => {
    expect(pathActive("/box/workouts", "/box/workouts")).toBe(true);
    expect(pathActive("/journal", "/box/workouts")).toBe(false);
    expect(pathActive("/journal/pantheon", "/box/workouts")).toBe(false);
  });
});
