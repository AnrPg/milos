import { describe, expect, it } from "vitest";

import { badgeKey, canSellOnline, fixLink, isHidden, onlineVisibility, salesPageHref, soldOnlineCount } from "./sold-online";

describe("sold-online (ADR-271)", () => {
  it("reads the API's online_visibility and never guesses a rule", () => {
    expect(onlineVisibility({ online_visibility: "purpose_off" })).toBe("purpose_off");
    expect(onlineVisibility({ online_visibility: "something-new" })).toBe("off");
    expect(onlineVisibility(null)).toBe("off");
  });

  it("maps each visibility to the list badge", () => {
    expect(badgeKey("visible")).toBe("badge");
    expect(badgeKey("no_provider")).toBe("badgeHidden");
    expect(badgeKey("purpose_off")).toBe("badgeHidden");
    expect(badgeKey("off")).toBeNull();
    expect(badgeKey("free")).toBeNull();
  });

  it("offers a fix only where the owner can fix it, in Ρυθμίσεις › Πληρωμές", () => {
    expect(fixLink("purpose_off")).toEqual({ href: "/admin/settings?tab=payments", labelKey: "fix_purpose_off" });
    expect(fixLink("no_provider")).toEqual({ href: "/admin/settings?tab=payments", labelKey: "fix_no_provider" });
    expect(fixLink("visible")).toBeNull();
    expect(fixLink("free")).toBeNull();
    expect(isHidden("visible")).toBe(false);
  });

  it("does not let free or retired packages be switched on", () => {
    expect(canSellOnline("free")).toBe(false);
    expect(canSellOnline("inactive")).toBe(false);
    expect(canSellOnline("off")).toBe(true);
  });

  it("counts N of M among the packages the API says can be sold online", () => {
    const packages = [
      { sold_online: true, online_visibility: "visible" },
      { sold_online: true, online_visibility: "purpose_off" },
      { sold_online: false, online_visibility: "off" },
      { sold_online: false, online_visibility: "free" },
    ];
    expect(soldOnlineCount(packages)).toEqual({ count: 2, total: 3 });
  });

  it("links the public Σελίδα πακέτων of the box", () => {
    expect(salesPageHref("kypseli")).toBe("/b/kypseli/packages");
    expect(salesPageHref(null)).toBeNull();
  });
});
