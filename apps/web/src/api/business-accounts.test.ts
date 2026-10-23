import { afterEach, describe, expect, it, vi } from "vitest";

import { demoSectionForPath, isAdminPath, isBusinessNotActivated } from "@/api/business-accounts";
import { ApiError, BUSINESS_NOT_ACTIVATED_EVENT, apiRequest } from "@/api/client";

describe("demo sections (ADR-184)", () => {
  it("maps each admin screen to the section its floating button fills", () => {
    expect(demoSectionForPath("/admin/users")).toBe("members");
    expect(demoSectionForPath("/org/box-a/admin/users/123")).toBe("members");
    expect(demoSectionForPath("/admin/schedule")).toBe("schedule");
    expect(demoSectionForPath("/admin/class-schedule")).toBe("schedule");
    expect(demoSectionForPath("/admin/finance/members")).toBe("finance");
    expect(demoSectionForPath("/admin/workouts")).toBe("workouts");
    expect(demoSectionForPath("/admin")).toBe("all");
    expect(demoSectionForPath("/admin/settings")).toBe("all");
    expect(demoSectionForPath("/admin/users-export")).toBe("all");
  });

  it("knows the admin screens", () => {
    expect(isAdminPath("/admin")).toBe(true);
    expect(isAdminPath("/org/box-a/admin/finance")).toBe(true);
    expect(isAdminPath("/box")).toBe(false);
    expect(isAdminPath("/administrators")).toBe(false);
  });
});

describe("business_not_activated", () => {
  afterEach(() => vi.restoreAllMocks());

  it("is recognised and announced once to the demo-mode host", async () => {
    const listener = vi.fn();
    window.addEventListener(BUSINESS_NOT_ACTIVATED_EVENT, listener);
    vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ code: "business_not_activated", error: "Not yet" }), { status: 403 }),
    );

    const failure = await apiRequest("/invitations", { method: "POST", token: "t" }).catch((error) => error);

    expect(failure).toBeInstanceOf(ApiError);
    expect(isBusinessNotActivated(failure)).toBe(true);
    expect(listener).toHaveBeenCalledTimes(1);
    window.removeEventListener(BUSINESS_NOT_ACTIVATED_EVENT, listener);
  });

  it("is not raised for other refusals", async () => {
    const listener = vi.fn();
    window.addEventListener(BUSINESS_NOT_ACTIVATED_EVENT, listener);
    vi.spyOn(window, "fetch").mockResolvedValue(new Response(JSON.stringify({ code: "forbidden" }), { status: 403 }));

    const failure = await apiRequest("/invitations", { method: "POST", token: "t" }).catch((error) => error);

    expect(isBusinessNotActivated(failure)).toBe(false);
    expect(listener).not.toHaveBeenCalled();
    window.removeEventListener(BUSINESS_NOT_ACTIVATED_EVENT, listener);
  });
});
