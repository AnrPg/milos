import { describe, expect, it } from "vitest";

import { billingProviderMemberships, isBillingProviderMembership } from "./billing-providers";

const membership = (roles: string[], organization: Record<string, unknown> = {}) => ({
  role: roles[0],
  roles,
  organization: { id: "o", name: "Box", slug: "box", ...organization },
});

describe("billing providers", () => {
  it("counts member and athlete roles at a gym or coach", () => {
    expect(isBillingProviderMembership(membership(["member"]))).toBe(true);
    expect(isBillingProviderMembership(membership(["athlete"], { provider_kind: "coach" }))).toBe(true);
    expect(isBillingProviderMembership(membership(["coach", "member"]))).toBe(true);
  });

  it("leaves out staff-only memberships, organisers and demo businesses", () => {
    expect(isBillingProviderMembership(membership(["owner", "coach"]))).toBe(false);
    expect(isBillingProviderMembership(membership(["member"], { provider_kind: "organiser" }))).toBe(false);
    expect(isBillingProviderMembership(membership(["member"], { activation: "demo" }))).toBe(false);
    expect(billingProviderMemberships([membership(["front_desk"]), membership(["member"], { activation: "active" })])).toHaveLength(1);
  });
});
