import { describe, expect, it } from "vitest";

import { resolveRoleRedirect } from "@/components/auth-guard";

describe("resolveRoleRedirect", () => {
  it("turns the global admin redirect into the selected tenant admin workspace", () => {
    expect(
      resolveRoleRedirect("/admin", {
        id: "membership-1",
        role: "admin",
        organization: {
          id: "org-1",
          name: "Test1",
          slug: "test1",
        },
        settings: {
          brand_name: "Test1",
          brand_logo_url: null,
          brand_primary_color: null,
        },
      }),
    ).toBe("/org/test1/admin");
  });

  it("leaves non-admin redirects untouched", () => {
    expect(resolveRoleRedirect("/", null)).toBe("/");
  });
});
