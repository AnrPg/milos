import { describe, expect, it, vi } from "vitest";

import {
  ADMIN_PROFILE_SECTION_REQUEST,
  openAdminProfileSection,
} from "@/components/admin/users/admin-profile-navigation";

describe("openAdminProfileSection", () => {
  it("requests expansion before scrolling to the selected section", () => {
    const section = document.createElement("article");
    section.id = "finance";
    section.scrollIntoView = vi.fn();
    document.body.append(section);
    const requested: string[] = [];
    window.addEventListener(ADMIN_PROFILE_SECTION_REQUEST, (event) => {
      requested.push((event as CustomEvent<{ section: string }>).detail.section);
    }, { once: true });
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
      callback(0);
      return 1;
    });

    openAdminProfileSection("finance");

    expect(requested).toEqual(["finance"]);
    expect(window.location.hash).toBe("#finance");
    expect(section.scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth", block: "start" });
    section.remove();
    vi.unstubAllGlobals();
  });
});
