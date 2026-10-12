import { describe, expect, it } from "vitest";

import {
  activeItemId,
  clientNavItems,
  sectionGroupFor,
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
  it("gives clients Home · Training · Journal", () => {
    expect(clientNavItems("member").map((item) => item.id)).toEqual(["home", "training", "journal"]);
    expect(clientNavItems("athlete")[1].href).toBe("/my-workouts");
  });

  it("marks history under Journal and my workouts under Training", () => {
    const items = clientNavItems("athlete");
    expect(activeItemId("/my-workouts/history", items)).toBe("journal");
    expect(activeItemId("/my-workouts", items)).toBe("training");
    expect(activeItemId("/", items)).toBe("home");
  });
});

describe("sectionGroupFor", () => {
  it("shows the Coaching tabs on the three coaching pages", () => {
    const staffItems = staffNavItems({ role: "admin", capabilities: ADMIN });
    const group = sectionGroupFor("/org/gym/admin/workouts/123", { surface: "admin", staffItems, features: [] });
    expect(group?.tabs.map((tab) => tab.id)).toEqual(["gymClasses", "personalTraining", "wodsVault"]);
    expect(sectionGroupFor("/org/gym/admin/finance", { surface: "admin", staffItems, features: [] })).toBeNull();
  });

  it("shows only entitled Training and Journal tabs", () => {
    const training = sectionGroupFor("/schedule", { surface: "member", staffItems: [], features: ["videos"] });
    expect(training?.tabs.map((tab) => tab.id)).toEqual(["classes", "videos"]);
    const journal = sectionGroupFor("/my-workouts/pantheon", { surface: "athlete", staffItems: [], features: [] });
    expect(journal?.id).toBe("journal");
  });
});
