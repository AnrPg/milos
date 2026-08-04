import { describe, expect, it } from "vitest";

import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";

describe("showsTenantSelfServiceSurfaces", () => {
  it("hides member and athlete account surfaces from platform owners", () => {
    expect(showsTenantSelfServiceSurfaces({ platform_owner: true })).toBe(false);
  });

  it("keeps self-service surfaces available to ordinary tenant users", () => {
    expect(showsTenantSelfServiceSurfaces({ platform_owner: false })).toBe(true);
    expect(showsTenantSelfServiceSurfaces({})).toBe(true);
  });
});
