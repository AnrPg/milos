import { describe, expect, it } from "vitest";

import { currentMemberPath, MEMBER_EXACT_MOVES, MEMBER_ROUTE_MOVES } from "@/lib/member-routes";

describe("currentMemberPath", () => {
  it("maps every moved page to its new home", () => {
    expect(currentMemberPath("/my-workouts")).toBe("/box/workouts");
    expect(currentMemberPath("/my-workouts/history")).toBe("/journal");
    expect(currentMemberPath("/my-workouts/pantheon")).toBe("/journal/progress");
    expect(currentMemberPath("/journal/pantheon")).toBe("/journal/progress");
    expect(currentMemberPath("/schedule")).toBe("/box/schedule");
    expect(currentMemberPath("/coaching")).toBe("/box/coach");
    expect(currentMemberPath("/profile")).toBe("/me/settings");
    expect(currentMemberPath("/account/billing")).toBe("/me/payments");
    expect(currentMemberPath("/account/activity/chats")).toBe("/messages");
  });

  it("opens the one inbox and the current pages from links the API used to store (ADR-196)", () => {
    expect(currentMemberPath("/account/activity/chats?thread=t1")).toBe("/messages?thread=t1");
    expect(currentMemberPath("/me/activity/chats?thread=t1")).toBe("/messages?thread=t1");
    expect(currentMemberPath("/me/messages?folder=requests")).toBe("/messages?folder=requests");
    expect(currentMemberPath("/me/messages/c-1")).toBe("/messages/c-1");
    expect(currentMemberPath("/box/shop/products/p-1")).toBe("/box/shop/product/p-1");
    expect(currentMemberPath("/journal/wellness")).toBe("/journal/wellbeing");
    expect(currentMemberPath("/partners")).toBe("/messages?filter=partners");
    expect(currentMemberPath("/partners/m-1")).toBe("/partners/m-1");
    expect(currentMemberPath("/me/settings/export")).toBe("/me/settings#journal-export");
  });

  it("keeps the query, hash and organization prefix", () => {
    expect(currentMemberPath("/schedule?open_slot=s1")).toBe("/box/schedule?open_slot=s1");
    expect(currentMemberPath("/profile#vault")).toBe("/me/settings#vault");
    expect(currentMemberPath("/org/kypseli/my-workouts?open=a1")).toBe("/org/kypseli/box/workouts?open=a1");
  });

  it("leaves other paths alone", () => {
    expect(currentMemberPath("/admin/coaching")).toBe("/admin/coaching");
    expect(currentMemberPath("/schedules")).toBe("/schedules");
    expect(currentMemberPath("/workouts/w1/execute")).toBe("/workouts/w1/execute");
    expect(currentMemberPath("https://example.com/schedule")).toBe("https://example.com/schedule");
  });

  it("never maps a destination again", () => {
    for (const [, to] of [...MEMBER_ROUTE_MOVES, ...MEMBER_EXACT_MOVES]) expect(currentMemberPath(to)).toBe(to);
  });
});
