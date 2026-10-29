import { describe, expect, it } from "vitest";

import { canBuyHere, hasPhysicalService } from "./store-policy";

const monthly = { "group_classes.included": true, "online_coaching.included": false };
const onlineOnly = { "group_classes.included": false, "online_coaching.included": true, "online_coaching.assigned_programming": true };
const classesAndOnline = { "group_classes.included": true, "online_coaching.included": true };

describe("store policy", () => {
  it("treats classes, personal training, assessments, open gym and events as physical services", () => {
    expect(hasPhysicalService(monthly)).toBe(true);
    expect(hasPhysicalService({ "personal_training.included": true })).toBe(true);
    expect(hasPhysicalService({ "personal_training.assessments": 2 })).toBe(true);
    expect(hasPhysicalService({ "facility.open_gym": true })).toBe(true);
    expect(hasPhysicalService({ "perks.events": true })).toBe(true);
  });

  it("treats Online programming, on-demand content and nutrition alone as digital", () => {
    expect(hasPhysicalService(onlineOnly)).toBe(false);
    expect(hasPhysicalService({ "content.on_demand_video": true, "online_coaching.nutrition_plan": true })).toBe(false);
    expect(hasPhysicalService({ "personal_training.assessments": 0 })).toBe(false);
  });

  it("sells everything on the web", () => {
    expect(canBuyHere({ kind: "subscription_package", fields: onlineOnly }, null)).toBe(true);
    expect(canBuyHere({ kind: "palee_plan" }, null)).toBe(true);
  });

  it("sells the box's physical services and goods in both apps", () => {
    for (const platform of ["ios", "android"] as const) {
      expect(canBuyHere({ kind: "subscription_package", fields: monthly }, platform)).toBe(true);
      expect(canBuyHere({ kind: "subscription_package", fields: classesAndOnline }, platform)).toBe(true);
      for (const kind of ["class_booking", "personal_training", "event_ticket", "shop_order", "invoice"] as const) {
        expect(canBuyHere({ kind }, platform)).toBe(true);
      }
    }
  });

  it("does not sell digital-only packages or the Plan (Palee) in the apps", () => {
    for (const platform of ["ios", "android"] as const) {
      expect(canBuyHere({ kind: "subscription_package", fields: onlineOnly }, platform)).toBe(false);
      expect(canBuyHere({ kind: "palee_plan" }, platform)).toBe(false);
    }
  });
});
