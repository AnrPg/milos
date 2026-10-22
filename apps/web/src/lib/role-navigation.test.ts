import { describe, expect, it } from "vitest";

import {
  activeItemId,
  clientExtraLinks,
  clientNavItems,
  likelyScreens,
  sectionGroupFor,
  showsBottomBar,
  staffNavItems,
  surfaceRole,
} from "@/lib/role-navigation";

const caps = (...names: string[]) => Object.fromEntries(names.map((name) => [name, "all"]));
const ADMIN = caps("grant_staff_roles", "manage_settings", "manage_coaching", "manage_workouts", "check_in", "run_classes", "take_payments", "view_directory", "view_finance_reports", "record_cleaning", "manage_cleaning_areas", "manage_inventory");
const COACH = caps("manage_coaching", "manage_workouts", "check_in", "run_classes", "view_directory", "report_inventory");
const DESK = caps("check_in", "run_classes", "take_payments", "view_directory", "review_cleaning", "manage_inventory");
const ACCOUNTANT = caps("take_payments", "view_billing_contacts", "view_finance_reports", "manage_billing");
const JANITOR = caps("record_cleaning", "report_inventory");

const ids = (capabilities: Record<string, string>, roles = ["admin"]) =>
  staffNavItems({ role: roles[0], roles, capabilities }).map((item) => item.id);

describe("staffNavItems", () => {
  it("gives owners and admins Home · Coaching · Finance · Users", () => {
    expect(ids(ADMIN)).toEqual(["home", "coaching", "finance", "users"]);
  });

  it("gives coaches Home · Coaching", () => {
    expect(ids(COACH, ["coach"])).toEqual(["home", "coaching"]);
  });

  it("gives front desk the desk links and accountants the money links", () => {
    expect(ids(DESK, ["front_desk"])).toEqual(["home", "checkIn", "classes", "finance", "clients", "inventory"]);
    expect(ids(ACCOUNTANT, ["accountant"])).toEqual(["home", "finance", "clients", "reports"]);
  });

  it("puts Κοινότητα in a coach's bar; owners and admins reach it from the dashboard (ADR-143)", () => {
    expect(ids({ ...COACH, moderate_community: "all" }, ["coach"])).toEqual(["home", "coaching", "community"]);
    expect(ids({ ...ADMIN, moderate_community: "all", manage_community: "all" })).toEqual(["home", "coaching", "finance", "users"]);
  });

  it("gives janitors only the cleaning log", () => {
    expect(ids(JANITOR, ["janitor"])).toEqual(["cleaning"]);
  });

  it("merges roles by union without duplicates", () => {
    expect(ids({ ...COACH, ...DESK }, ["coach", "front_desk"])).toEqual(["home", "coaching", "finance", "inventory"]);
    expect(ids({ ...DESK, ...ACCOUNTANT }, ["front_desk", "accountant"])).toEqual([
      "home",
      "checkIn",
      "classes",
      "finance",
      "clients",
      "reports",
      "inventory",
    ]);
  });
});

describe("surfaceRole", () => {
  it("opens staff pages for any staff role and client pages on My training", () => {
    const coachAthlete = { role: "coach", roles: ["coach", "athlete"] };
    expect(surfaceRole(coachAthlete)).toBe("admin");
    expect(surfaceRole(coachAthlete, "client")).toBe("athlete");
    expect(surfaceRole({ role: "coach", roles: ["coach"] }, "client")).toBe("admin");
    expect(surfaceRole({ role: "member" })).toBe("member");
    expect(surfaceRole({ role: "janitor", roles: ["janitor", "member"] })).toBe("member");
  });
});

describe("client navigation", () => {
  it("gives clients the four fixed tabs: Αρχική · Box · Ημερολόγιο · Εγώ", () => {
    expect(clientNavItems().map((item) => item.id)).toEqual(["home", "box", "journal", "me"]);
    expect(clientNavItems().map((item) => item.href)).toEqual(["/", "/box", "/journal", "/me"]);
  });

  it("lights the tab that is each member page's home", () => {
    const items = clientNavItems();
    const owner = (path: string) => activeItemId(path, items);
    expect(owner("/")).toBe("home");
    for (const path of ["/box", "/box/workouts", "/box/schedule", "/box/appointments", "/box/videos", "/box/coach", "/workouts", "/class-timer/s1/display"]) {
      expect(owner(path)).toBe("box");
    }
    for (const path of ["/journal", "/journal/vault", "/journal/progress", "/journal/pantheon", "/journal/wellbeing", "/journal/reviews"]) {
      expect(owner(path)).toBe("journal");
    }
    for (const path of ["/me", "/me/settings", "/me/payments", "/me/activity/chats"]) {
      expect(owner(path)).toBe("me");
    }
    expect(owner("/org/kypseli/box/schedule")).toBe("box");
  });

  it("keeps the cleaning and inventory links out of the bar", () => {
    const janitorMember = { role: "member", roles: ["member", "janitor"], capabilities: { record_cleaning: "own", report_inventory: "own" } };
    expect(clientExtraLinks(janitorMember).map((item) => item.id)).toEqual(["cleaning", "inventory"]);
    expect(clientExtraLinks({ role: "member" })).toEqual([]);
  });

  it("hides the bar on full-screen workout and class-timer pages only", () => {
    expect(showsBottomBar("/workouts/w1/execute")).toBe(false);
    expect(showsBottomBar("/workouts/free-text/execute")).toBe(false);
    expect(showsBottomBar("/org/kypseli/class-timer/s1/display")).toBe(false);
    expect(showsBottomBar("/workouts")).toBe(true);
    expect(showsBottomBar("/box")).toBe(true);
  });
});

describe("sectionGroupFor", () => {
  it("shows the Coaching tabs on the three coaching pages", () => {
    const staffItems = staffNavItems({ role: "admin", capabilities: ADMIN });
    const group = sectionGroupFor("/org/gym/admin/workouts/123", { surface: "admin", staffItems, features: [] });
    expect(group?.tabs.map((tab) => tab.id)).toEqual(["gymClasses", "personalTraining", "wodsVault"]);
    expect(sectionGroupFor("/org/gym/admin/finance", { surface: "admin", staffItems, features: [] })).toBeNull();
  });

  it("shows only entitled Box sub-pages, and every Journal segment to everyone", () => {
    const box = sectionGroupFor("/box/schedule", { surface: "member", staffItems: [], features: ["videos"] });
    expect(box?.tabs.map((tab) => tab.id)).toEqual(["boxToday", "myWorkouts", "classes", "videos"]);
    const journal = sectionGroupFor("/journal/pantheon", { surface: "athlete", staffItems: [], features: [] });
    expect(journal?.tabs.map((tab) => tab.id)).toEqual(["flow", "vault", "body", "wellbeing", "progress"]);
    expect(journal?.tabs.find((tab) => tab.id === "progress")?.match).toContain("/journal/pantheon");
    // ADR-164: the anatomy atlas lives under Πρόοδος.
    expect(journal?.tabs.find((tab) => tab.id === "progress")?.match).toContain("/journal/atlas");
    expect(sectionGroupFor("/box", { surface: "member", staffItems: [], features: ["videos"] })).toBeNull();
    const entitled = sectionGroupFor("/journal", { surface: "athlete", staffItems: [], features: ["progress", "coaching"] });
    expect(entitled?.tabs.map((tab) => tab.id)).toContain("progress");
  });

  it("drops Σώμα and Ευεξία when switched off in Ρυθμίσεις › Σώμα (ADR-158)", () => {
    const off = sectionGroupFor("/journal/body", {
      surface: "member",
      staffItems: [],
      features: [],
      journalSections: { body: false, wellness: false },
    });
    expect(off?.tabs.map((tab) => tab.id)).toEqual(["flow", "vault", "progress"]);
    const on = sectionGroupFor("/journal/body/new", { surface: "member", staffItems: [], features: [], journalSections: { body: true } });
    expect(on?.id).toBe("journal");
    expect(activeItemId("/journal/body/new", on!.tabs)).toBe("body");
  });
});

describe("likelyScreens", () => {
  const hrefs = (surface: "admin" | "member" | "athlete", capabilities: Record<string, string> = {}) =>
    likelyScreens(surface, surface === "admin" ? staffNavItems({ role: "admin", capabilities }) : []).map((item) => item.href);

  it("preloads at least six distinct screens for owners and members", () => {
    for (const screens of [hrefs("admin", ADMIN), hrefs("member"), hrefs("athlete")]) {
      expect(screens.length).toBeGreaterThanOrEqual(6);
      expect(new Set(screens).size).toBe(screens.length);
    }
  });

  it("starts with the bar links, then the most used sub-pages", () => {
    expect(hrefs("member").slice(0, 4)).toEqual(clientNavItems().map((item) => item.href));
    expect(hrefs("admin", ADMIN)).toEqual(expect.arrayContaining(["/admin", "/admin/class-schedule", "/admin/coaching-assignments", "/admin/workouts", "/admin/settings"]));
  });

  it("only preloads what a staff role can open", () => {
    expect(hrefs("admin", JANITOR)).toEqual(["/admin/cleaning"]);
    expect(hrefs("admin", COACH)).not.toContain("/admin/settings");
  });
});
