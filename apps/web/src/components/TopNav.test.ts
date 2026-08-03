import { describe, expect, it } from "vitest";

import { pathActive } from "@/components/TopNav";

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
