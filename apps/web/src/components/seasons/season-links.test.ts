import { describe, expect, it } from "vitest";

import { cleanProgramme, memberSeasonAction, programmeDate } from "@/api/seasons";
import { notificationTargetUrl } from "@/components/notifications/notification-links";

import { seasonNotificationText, seasonNotificationUrl } from "./season-links";
import { seasonErrorKey, seasonRange } from "./season-ui";
import { ApiError } from "@/api/client";

const t = (key: string, values?: Record<string, string | number>) =>
  values ? `${key}(${Object.entries(values).map(([k, v]) => `${k}=${v}`).join(",")})` : key;

describe("season notifications (ADR-167)", () => {
  it("opens the builder for staff and Box for members", () => {
    expect(seasonNotificationUrl("season_requested", { season_id: "s-1" })).toBe("/admin/finance?tab=seasons&season=s-1");
    expect(seasonNotificationUrl("season_confirmed", { season_id: "s-1" })).toBe("/box?season=s-1");
    expect(seasonNotificationUrl("season_declined", {})).toBe("/box");
    expect(seasonNotificationUrl("buddy_invite", {})).toBeNull();
    expect(notificationTargetUrl({ type: "season_cancelled", payload: { season_id: "s-2" } }, "member")).toBe("/box?season=s-2");
  });

  it("names the season, the person and the box, with a decline reason", () => {
    expect(seasonNotificationText("season_requested", { season_title: "Hyrox", person_nickname: "Eleni", enrollment_status: "waitlisted" }, "body", t)).toBe(
      "notif.season_requested.bodyWaitlist(season=Hyrox,person=Eleni,box=notif.theBox)",
    );
    expect(seasonNotificationText("season_declined", { season_title: "Hyrox", box_name: "Box 1", reason: "Γεμάτο" }, "body", t)).toBe(
      "notif.season_declined.body(season=Hyrox,person=notif.someone,box=Box 1) «Γεμάτο»",
    );
    expect(seasonNotificationText("season_confirmed", {}, "title", t)).toBe(
      "notif.season_confirmed.title(season=notif.aSeason,person=notif.someone,box=notif.theBox)",
    );
    expect(seasonNotificationText("trial_requested", {}, "title", t)).toBeNull();
  });
});

describe("season helpers", () => {
  it("offers request, withdraw or nothing", () => {
    expect(memberSeasonAction({ status: "published", mine: null })).toBe("request");
    expect(memberSeasonAction({ status: "running", mine: { id: "e", status: "declined" } })).toBe("request");
    expect(memberSeasonAction({ status: "published", mine: { id: "e", status: "waitlisted" } })).toBe("cancel");
    expect(memberSeasonAction({ status: "running", mine: { id: "e", status: "active" } })).toBeNull();
    expect(memberSeasonAction({ status: "completed", mine: null })).toBeNull();
  });

  it("keeps programme rows inside the season, once each, by day", () => {
    expect(
      cleanProgramme(
        [
          { day: 9, workout_id: "b" },
          { day: "0", workout_id: "a" },
          { day: 0, workout_id: "a" },
          { day: 14, workout_id: "a" },
          { day: 3, workout_id: "" },
        ],
        2,
      ),
    ).toEqual([
      { day: 0, workout_id: "a" },
      { day: 9, workout_id: "b" },
    ]);
  });

  it("dates programme days and ranges", () => {
    expect(programmeDate("2026-11-02", 6)).toBe("2026-11-08");
    expect(programmeDate("nope", 1)).toBe("");
    expect(seasonRange("en", "2026-11-02", "2026-11-15")).toBe("Nov 2 – Nov 15");
  });

  it("maps season error codes and falls back", () => {
    expect(seasonErrorKey(new ApiError(409, "full", { error: "full", code: "season_full" }))).toBe("error_season_full");
    expect(seasonErrorKey(new ApiError(500, "x", { error: "x" }))).toBe("error_generic");
    expect(seasonErrorKey(new Error("x"))).toBe("error_generic");
  });
});
