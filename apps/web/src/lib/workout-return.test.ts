import { describe, expect, it } from "vitest";

import { newWorkoutHref, safeReturnPath, workoutPublishedHref } from "./workout-return";

describe("workout return", () => {
  it("keeps only paths inside the app", () => {
    expect(safeReturnPath("/org/box/admin/class-schedule")).toBe("/org/box/admin/class-schedule");
    expect(safeReturnPath("/a?b=1")).toBe("/a?b=1");
    expect(safeReturnPath("//evil.example/x")).toBeNull();
    expect(safeReturnPath("/\\evil.example")).toBeNull();
    expect(safeReturnPath("https://evil.example")).toBeNull();
    expect(safeReturnPath(null)).toBeNull();
  });

  it("sends the coach back with the published WOD", () => {
    const params = new URLSearchParams(newWorkoutHref("/admin/workouts/new", "/org/box/admin/class-schedule?x=1").split("?")[1]);
    expect(workoutPublishedHref(params, "w-1", "/admin/workouts")).toBe("/org/box/admin/class-schedule?x=1&wod=w-1");
  });

  it("falls back to the library without a safe return path", () => {
    expect(workoutPublishedHref(new URLSearchParams(), "w-1", "/admin/workouts")).toBe("/admin/workouts");
    expect(workoutPublishedHref(new URLSearchParams("return_to=//evil"), "w-1", "/admin/workouts")).toBe("/admin/workouts");
  });
});
