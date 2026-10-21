import { describe, expect, it } from "vitest";

import { notificationOrigin } from "@/components/notifications/notification-origin";
import { paletteColor } from "@/lib/provider-sources";

const ORGANIZATIONS = [
  { id: "org-a", name: "Atlas Gym" },
  { id: "org-b", name: "Boreas Strength" },
];

describe("notificationOrigin", () => {
  it("stays quiet for notifications from the active organization", () => {
    expect(notificationOrigin("org-a", "org-a", ORGANIZATIONS, "Another gym")).toBeNull();
  });

  it("names the originating organization when it differs from the active one", () => {
    expect(notificationOrigin("org-a", "org-b", ORGANIZATIONS, "Another gym")).toEqual({
      name: "Atlas Gym",
      color: paletteColor("org-a"),
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
});
