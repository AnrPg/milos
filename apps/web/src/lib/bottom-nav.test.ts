import { describe, expect, it } from "vitest";

import {
  bottomNavEntries,
  bottomNavHiddenRoute,
  nextScrollHidden,
  routeShowsBottomNav,
  usesMemberShell,
} from "@/lib/bottom-nav";
import { surfaceRole } from "@/lib/role-navigation";

const ids = () => bottomNavEntries().map((entry) => (entry.kind === "messages" ? "messages" : entry.item.id));

describe("bottomNavEntries", () => {
  it("holds Feed · Box · Journal · Μηνύματα · avatar, with Μηνύματα next to the avatar", () => {
    expect(ids()).toEqual(["home", "box", "journal", "messages", "me"]);
    const labels = bottomNavEntries().flatMap((entry) => (entry.kind === "messages" ? [] : [entry.item.labelKey]));
    expect(labels).toEqual(["feed", "box", "journal", "me"]);
  });
});

describe("hidden routes", () => {
  it("hides the bar on focused, full-screen flows", () => {
    for (const path of [
      "/workouts/w1/execute",
      "/workouts/free-text/execute",
      "/org/kypseli/workouts/w1/execute",
      "/class-timer/s1/display",
      "/class-timer/s1/control",
      "/tv",
      "/admin/check-in/door/loc-1",
      "/org/kypseli/admin/check-in/poster/loc-1",
      "/c/loc-1/code",
      "/welcome",
      "/login",
      "/register",
      "/forgot-password",
      "/reset-password",
      "/sign-out-everywhere",
      "/confirm-email-change",
      "/revert-email-change",
      "/account-deletion/confirm",
      "/account-deletion/undo",
      "/join/kypseli",
      "/invite",
      "/set-admin",
      "/activate-business",
      "/platform/organizations",
    ]) {
      expect(routeShowsBottomNav(path), path).toBe(false);
    }
    expect(bottomNavHiddenRoute("/workouts/w1/execute?from=box")).toBe("workoutExecution");
  });

  it("shows it on every member page", () => {
    for (const path of ["/", "/around", "/box", "/box/schedule", "/workouts", "/workouts/w1", "/journal", "/journal/progress", "/me", "/me/settings", "/b/kypseli", "/clubs/c1"]) {
      expect(routeShowsBottomNav(path), path).toBe(true);
    }
  });
});

describe("usesMemberShell", () => {
  const base = { signedIn: true, loading: false, vendor: false, accountRole: "member" };

  it("gives the bar to a signed-in person with no gym or coach", () => {
    expect(usesMemberShell({ ...base, membershipCount: 0, surfaceRole: "member" })).toBe(true);
  });

  it("gives it to members and athletes, and to staff in the social app", () => {
    expect(usesMemberShell({ ...base, membershipCount: 1, surfaceRole: "member" })).toBe(true);
    expect(usesMemberShell({ ...base, membershipCount: 1, surfaceRole: "athlete" })).toBe(true);
    const owner = { role: "owner", roles: ["owner"] };
    expect(usesMemberShell({ ...base, membershipCount: 1, surfaceRole: surfaceRole(owner, "client") })).toBe(true);
    expect(usesMemberShell({ ...base, membershipCount: 1, surfaceRole: surfaceRole(owner, "staff") })).toBe(false);
  });

  it("keeps it away while loading, signed out, and for a vendor or admin without a box", () => {
    expect(usesMemberShell({ ...base, loading: true, membershipCount: 0, surfaceRole: "member" })).toBe(false);
    expect(usesMemberShell({ ...base, signedIn: false, membershipCount: 0, surfaceRole: "member" })).toBe(false);
    expect(usesMemberShell({ ...base, vendor: true, membershipCount: 0, surfaceRole: "member" })).toBe(false);
    expect(usesMemberShell({ ...base, accountRole: "admin", membershipCount: 0, surfaceRole: "member" })).toBe(false);
  });
});

describe("nextScrollHidden", () => {
  it("hides on scroll down, shows on scroll up and near the top", () => {
    expect(nextScrollHidden({ hidden: false, lastY: 100 }, 200)).toBe(true);
    expect(nextScrollHidden({ hidden: true, lastY: 300 }, 250)).toBe(false);
    expect(nextScrollHidden({ hidden: true, lastY: 300 }, 20)).toBe(false);
    // Small jitters change nothing.
    expect(nextScrollHidden({ hidden: true, lastY: 300 }, 297)).toBe(true);
  });
});
