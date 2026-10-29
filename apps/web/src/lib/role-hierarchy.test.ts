import { describe, expect, it } from "vitest";

import { canManageMember, editableRoles, grantableRoles, selfAssignableRoles, topTier } from "./role-hierarchy";

// Mirrors MembershipPolicyTest on the API (ADR-099, ADR-219).
describe("role hierarchy", () => {
  it("ranks owner over admin over staff over clients", () => {
    expect(topTier(["member", "admin"])).toBeGreaterThan(topTier(["coach", "janitor"]));
    expect(topTier(["owner"])).toBeGreaterThan(topTier(["admin"]));
    expect(topTier(["guest"])).toBeLessThan(topTier(["member"]));
    expect(topTier(["guest"])).toBeGreaterThan(topTier([]));
    expect(topTier([])).toBe(0);
  });

  it("acts only on people ranked below; owners also on co-owners", () => {
    expect(canManageMember(["admin"], ["coach", "member"])).toBe(true);
    expect(canManageMember(["admin"], ["admin"])).toBe(false);
    expect(canManageMember(["admin", "coach"], ["owner", "member"])).toBe(false);
    expect(canManageMember(["owner"], ["owner"])).toBe(true);
  });

  it("lets someone toggle only roles below their own top role on themselves", () => {
    expect(selfAssignableRoles(["owner"])).not.toContain("owner");
    expect(selfAssignableRoles(["owner"])).toEqual(expect.arrayContaining(["admin", "coach", "member"]));
    expect(selfAssignableRoles(["admin", "coach"])).toEqual(["coach", "front_desk", "accountant", "janitor", "member", "athlete"]);
    expect(selfAssignableRoles(["coach"])).toEqual(["member", "athlete"]);
    expect(selfAssignableRoles(["member"])).toEqual([]);
    expect(selfAssignableRoles(["guest"])).toEqual([]);
  });

  it("gives nothing to edit on a fellow admin or an owner", () => {
    expect(editableRoles(["admin"], ["admin"], false)).toEqual([]);
    expect(editableRoles(["admin"], ["owner"], false)).toEqual([]);
    expect(editableRoles(["admin"], ["coach"], false)).toEqual(grantableRoles(["admin"]));
    expect(editableRoles(["admin"], ["admin"], true)).not.toContain("admin");
  });
});
