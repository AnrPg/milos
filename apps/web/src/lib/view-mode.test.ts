import { describe, expect, it } from "vitest";

import { surfaceRole } from "@/lib/role-navigation";
import { DEFAULT_VIEW, isConsolePath, parseStoredView, viewFor } from "@/lib/view-mode";

describe("view mode (ADR-103, amended 2026-10-23)", () => {
  it("defaults staff to the console, remembered per device", () => {
    expect(DEFAULT_VIEW).toBe("staff");
    expect(parseStoredView(null)).toBe("staff");
    expect(parseStoredView("garbage")).toBe("staff");
    expect(parseStoredView("client")).toBe("client");
    expect(surfaceRole({ role: "owner", roles: ["owner"] }, parseStoredView(null))).toBe("admin");
  });

  it("lets every staff member switch to the social app, client role or not", () => {
    for (const role of ["owner", "admin", "coach", "front_desk", "accountant"]) {
      expect(surfaceRole({ role, roles: [role] }, "client"), role).toBe("member");
    }
    expect(surfaceRole({ role: "coach", roles: ["coach", "athlete"] }, "client")).toBe("athlete");
  });

  it("opens the console on its URLs whatever was stored", () => {
    for (const path of ["/admin", "/admin/users", "/org/kypseli/admin", "/org/kypseli/admin/check-in/door/l1"]) {
      expect(isConsolePath(path), path).toBe(true);
      expect(viewFor(path, "client"), path).toBe("staff");
    }
    for (const path of ["/", "/me", "/org/kypseli", "/administer", "/box"]) {
      expect(isConsolePath(path), path).toBe(false);
      expect(viewFor(path, "client"), path).toBe("client");
    }
    expect(viewFor("/", "staff")).toBe("staff");
  });

  it("never changes people without a staff role", () => {
    expect(surfaceRole({ role: "member" }, "staff")).toBe("member");
    expect(surfaceRole({ role: "athlete" }, "staff")).toBe("athlete");
  });
});
