import { describe, expect, it } from "vitest";

import { notificationOrigin } from "@/components/notifications/notification-origin";

const ORGANIZATIONS = [
  { id: "org-a", name: "Atlas Gym", brandColor: "#ff8800" },
  { id: "org-b", name: "Boreas Strength", brandColor: null },
];

describe("notificationOrigin", () => {
  it("stays quiet for notifications from the active organization", () => {
    expect(notificationOrigin("org-a", "org-a", ORGANIZATIONS, "Another gym")).toBeNull();
  });

  it("names the originating organization when it differs from the active one", () => {
    expect(notificationOrigin("org-a", "org-b", ORGANIZATIONS, "Another gym")).toEqual({
      name: "Atlas Gym",
      color: "#ff8800",
    });
  });

  it("falls back to no colour when the organization has no brand colour", () => {
    expect(notificationOrigin("org-b", "org-a", ORGANIZATIONS, "Another gym")).toEqual({
      name: "Boreas Strength",
      color: null,
    });
  });

  it("still flags an organization the user can no longer see", () => {
    expect(notificationOrigin("org-gone", "org-a", ORGANIZATIONS, "Another gym")).toEqual({
      name: "Another gym",
      color: null,
    });
  });

  it("stays quiet when the notification carries no organization", () => {
    expect(notificationOrigin(null, "org-a", ORGANIZATIONS, "Another gym")).toBeNull();
    expect(notificationOrigin(undefined, "org-a", ORGANIZATIONS, "Another gym")).toBeNull();
  });

  it("stays quiet when no organization is active, rather than flagging everything", () => {
    expect(notificationOrigin("org-a", null, ORGANIZATIONS, "Another gym")).toBeNull();
  });

  it("treats a blank brand colour as no colour", () => {
    expect(
      notificationOrigin("org-c", "org-a", [{ id: "org-c", name: "Ceres", brandColor: "   " }], "x"),
    ).toEqual({ name: "Ceres", color: null });
  });
});
