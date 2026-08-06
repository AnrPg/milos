import { describe, expect, it } from "vitest";

import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";

describe("showsTenantSelfServiceSurfaces", () => {
  it("hides member and athlete account surfaces from vendors", () => {
    expect(showsTenantSelfServiceSurfaces({ vendor: true })).toBe(false);
  });

  it("keeps self-service surfaces available to ordinary tenant users", () => {
    expect(showsTenantSelfServiceSurfaces({ vendor: false })).toBe(true);
    expect(showsTenantSelfServiceSurfaces({})).toBe(true);
  });
});
