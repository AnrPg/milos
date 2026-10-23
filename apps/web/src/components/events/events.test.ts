import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import type { CommunityEvent } from "@/api/events";

import {
  dateBlock,
  eventErrorKey,
  eventHostMode,
  eventRequest,
  formFromEvent,
  formProblem,
  formProblems,
  formatPrice,
  hasEnded,
  isLateCancel,
  localInputs,
  localInstant,
  optimisticRsvp,
  parsePriceCents,
  placeAddress,
  placeName,
  rsvpState,
  splitEvents,
  type EventForm,
} from "./events";
import { patchEventIn } from "./use-events";

const NOW = new Date("2026-10-20T10:00:00Z");
const inHours = (hours: number) => new Date(NOW.getTime() + hours * 3_600_000).toISOString();

function event(overrides: Partial<CommunityEvent> = {}): CommunityEvent {
  return {
    id: "event-1",
    organization_id: "org-1",
    club_id: "club-1",
    time_zone: "Europe/Athens",
    club: { id: "club-1", name: "Box Kypseli", kind: "gym" },
    box: { name: "Box Kypseli", slug: "kypseli", logo_url: null },
    title: "Open WOD",
    starts_at: inHours(24),
    ends_at: inHours(25),
    place: { name: "Box Kypseli", address: "Fokionos 1", latitude: null, longitude: null, location_id: "loc-1" },
    capacity: 10,
    spots_left: 3,
    going_count: 7,
    waitlist_count: 0,
    price_cents: 0,
    currency: "EUR",
    open_to_non_members: false,
    guest_pass_allowed: false,
    guests_per_member: 0,
    good_for_friends: false,
    cancelled: false,
    can_rsvp: true,
    can_manage: false,
    my: null,
    audience: "club",
    host: { kind: "business", organization_id: "org-1", name: "Box Kypseli", slug: "kypseli", logo_url: null, person: null },
    cohosts: [],
    ...overrides,
  };
}

const going = { status: "going" as const, source: "member" as const, paid: false, late_cancel: false };

describe("rsvpState", () => {
  it("offers a place, the waitlist when full, and nothing once cancelled or started", () => {
    expect(rsvpState(event(), NOW)).toBe("join");
    expect(rsvpState(event({ spots_left: 0 }), NOW)).toBe("join_waitlist");
    expect(rsvpState(event({ capacity: null, spots_left: null }), NOW)).toBe("join");
    expect(rsvpState(event({ my: going }), NOW)).toBe("going");
    expect(rsvpState(event({ my: { ...going, status: "waitlisted" } }), NOW)).toBe("waitlisted");
    expect(rsvpState(event({ my: { ...going, status: "cancelled" } }), NOW)).toBe("join");
    expect(rsvpState(event({ cancelled: true, my: going }), NOW)).toBe("cancelled");
    expect(rsvpState(event({ starts_at: inHours(-1) }), NOW)).toBe("over");
    expect(rsvpState(event({ can_rsvp: false }), NOW)).toBe("closed");
  });
});

describe("late cancels", () => {
  it("warns only when giving up a held place within 2 hours of the start", () => {
    expect(isLateCancel(event({ my: going, starts_at: inHours(1.5) }), NOW)).toBe(true);
    expect(isLateCancel(event({ my: going, starts_at: inHours(2) }), NOW)).toBe(true);
    expect(isLateCancel(event({ my: going, starts_at: inHours(3) }), NOW)).toBe(false);
    expect(isLateCancel(event({ my: { ...going, status: "waitlisted" }, starts_at: inHours(1) }), NOW)).toBe(false);
    expect(isLateCancel(event({ my: going, starts_at: inHours(-0.5) }), NOW)).toBe(false);
  });

  it("knows when an event has ended", () => {
    expect(hasEnded(event({ ends_at: inHours(-1) }), NOW)).toBe(true);
    expect(hasEnded(event(), NOW)).toBe(false);
  });
});

describe("formatting", () => {
  it("formats prices without cents when whole, and free as null", () => {
    expect(formatPrice(0, "EUR", "en")).toBeNull();
    expect(formatPrice(1500, "EUR", "en")).toBe("€15");
    expect(formatPrice(1250, "EUR", "en")).toBe("€12.50");
    expect(formatPrice(1250, "EUR", "el")).toMatch(/12,50/);
  });

  it("builds the date block from the weekday and day of the month", () => {
    expect(dateBlock("2026-10-24T09:00:00Z", "en", "UTC")).toEqual({ weekday: "SAT", day: "24" });
    expect(dateBlock("2026-10-24T09:00:00Z", "el", "UTC").day).toBe("24");
  });

  it("names a place by its name, else its address, with the rest under it", () => {
    expect(placeName({ name: null, address: "Fokionos 1", latitude: null, longitude: null, location_id: null })).toBe("Fokionos 1");
    expect(placeAddress({ name: "Park", address: "Fokionos 1", city: "Athens", latitude: null, longitude: null, location_id: null })).toBe(
      "Fokionos 1, Athens",
    );
  });
});

describe("splitEvents", () => {
  it("lists upcoming soonest first and past latest first", () => {
    const a = event({ id: "a", starts_at: inHours(48), ends_at: inHours(49) });
    const b = event({ id: "b", starts_at: inHours(2), ends_at: inHours(3) });
    const c = event({ id: "c", starts_at: inHours(-30), ends_at: inHours(-29) });
    const d = event({ id: "d", starts_at: inHours(-5), ends_at: inHours(-4) });
    const { upcoming, past } = splitEvents([a, c, b, d], NOW);
    expect(upcoming.map((entry) => entry.id)).toEqual(["b", "a"]);
    expect(past.map((entry) => entry.id)).toEqual(["d", "c"]);
  });
});

describe("optimisticRsvp", () => {
  it("takes a place while one is left, else joins the waitlist", () => {
    const taken = optimisticRsvp(event(), true);
    expect(taken.my?.status).toBe("going");
    expect(taken.going_count).toBe(8);
    expect(taken.spots_left).toBe(2);

    const waiting = optimisticRsvp(event({ spots_left: 0 }), true);
    expect(waiting.my?.status).toBe("waitlisted");
    expect(waiting.going_count).toBe(7);
    expect(waiting.waitlist_count).toBe(1);
  });

  it("frees a place, which goes to the first person waiting", () => {
    const freed = optimisticRsvp(event({ my: going }), false);
    expect(freed.my?.status).toBe("cancelled");
    expect(freed.going_count).toBe(6);
    expect(freed.spots_left).toBe(4);

    const handedOn = optimisticRsvp(event({ my: going, spots_left: 0, waitlist_count: 2 }), false);
    expect(handedOn.going_count).toBe(7);
    expect(handedOn.waitlist_count).toBe(1);
    expect(handedOn.spots_left).toBe(0);

    const leftQueue = optimisticRsvp(event({ my: { ...going, status: "waitlisted" }, waitlist_count: 2 }), false);
    expect(leftQueue.waitlist_count).toBe(1);
    expect(leftQueue.going_count).toBe(7);
  });

  it("changes nothing when answering the same twice", () => {
    const already = event({ my: going });
    expect(optimisticRsvp(already, true)).toBe(already);
    const none = event();
    expect(optimisticRsvp(none, false)).toBe(none);
  });
});

describe("the create form", () => {
  const form: EventForm = {
    title: " Run 8 km ",
    description: "",
    date: "2026-10-25",
    time: "09:30",
    durationMinutes: 90,
    place: { kind: "address", name: "Lycabettus", address: "" },
    capacity: "30",
    paid: true,
    price: "15,5",
    openToAll: true,
    guestPass: true,
    guestsPerMember: 2,
    goodForFriends: true,
    repeatWeekly: true,
    repeatUntil: "2026-12-20",
    coverMediaId: null,
    timeZone: null,
  };

  it("parses prices in either decimal style", () => {
    expect(parsePriceCents("15")).toBe(1500);
    expect(parsePriceCents("15,5")).toBe(1550);
    expect(parsePriceCents("12.05")).toBe(1205);
    expect(parsePriceCents("abc")).toBeNull();
    expect(parsePriceCents("1.234")).toBeNull();
  });

  it("round-trips local dates and times", () => {
    const instant = localInstant("2026-10-25", "09:30")!;
    expect(localInputs(instant.toISOString())).toEqual({ date: "2026-10-25", time: "09:30" });
    expect(localInstant("2026-10-25", "")).toBeNull();
  });

  it("reads the date and time on the event's clock, whatever the device's", () => {
    expect(localInstant("2026-10-24", "19:00", "Europe/Athens")!.toISOString()).toBe("2026-10-24T16:00:00.000Z");
    expect(localInstant("2026-11-03", "19:00", "Europe/Athens")!.toISOString()).toBe("2026-11-03T17:00:00.000Z");
    expect(localInputs("2026-10-24T16:00:00Z", "America/New_York")).toEqual({ date: "2026-10-24", time: "12:00" });
  });

  it("sends an event's own zone only when it differs from the gym's", () => {
    const athens = { ...form, timeZone: "Europe/Athens" };
    expect(eventRequest(athens, { gymTimeZone: "Europe/Athens" }).time_zone).toBeNull();
    expect(eventRequest({ ...form, timeZone: "Europe/Madrid" }, { gymTimeZone: "Europe/Athens" }).time_zone).toBe("Europe/Madrid");
    expect("time_zone" in eventRequest(athens)).toBe(false);
    expect(eventRequest({ ...form, date: "2026-10-24", time: "19:00", timeZone: "Europe/Athens" }).starts_at).toBe("2026-10-24T16:00:00.000Z");
  });

  it("says what is missing", () => {
    expect(formProblem(form, NOW)).toBeNull();
    expect(formProblem({ ...form, title: " " }, NOW)).toBe("title");
    expect(formProblem({ ...form, date: "2026-10-19" }, NOW)).toBe("past");
    expect(formProblem({ ...form, date: "2026-10-19" }, NOW, { editing: true })).toBeNull();
    expect(formProblem({ ...form, place: { kind: "address", name: "", address: "" } }, NOW)).toBe("place");
    expect(formProblem({ ...form, capacity: "0" }, NOW)).toBe("capacity");
    expect(formProblem({ ...form, price: "" }, NOW)).toBe("price");
    expect(formProblem({ ...form, repeatUntil: "2026-10-01" }, NOW)).toBe("repeat");
  });

  it("lists every problem at once, in the order the fields are asked", () => {
    expect(formProblems(form, NOW)).toEqual([]);
    expect(formProblems({ ...form, title: "", capacity: "0", price: "" }, NOW)).toEqual(["title", "capacity", "price"]);
    expect(formProblems({ ...form, date: "x" }, NOW)).toEqual(["when", "repeat"]);
  });

  it("builds the request, with the end from the duration and weekly repeat", () => {
    const body = eventRequest(form);
    expect(body.title).toBe("Run 8 km");
    expect(new Date(body.ends_at).getTime() - new Date(body.starts_at).getTime()).toBe(90 * 60_000);
    expect(body).toMatchObject({
      location_id: null,
      place_name: "Lycabettus",
      address: null,
      capacity: 30,
      price_cents: 1550,
      open_to_non_members: true,
      guest_pass_allowed: true,
      guests_per_member: 2,
      good_for_friends: true,
      repeat_until: "2026-12-20",
    });
  });

  it("tags «Καλό για φίλους» only where a friend can come", () => {
    expect(eventRequest({ ...form, openToAll: false, guestPass: false }).good_for_friends).toBe(false);
    expect(eventRequest({ ...form, openToAll: false }).good_for_friends).toBe(true);
    expect(eventRequest({ ...form, groupOnly: true }, { group: true }).good_for_friends).toBe(false);
  });

  it("lets a member group's admin pick the price, who it is for and guest passes (ADR-185)", () => {
    expect(eventRequest({ ...form, groupOnly: true }, { group: true })).toMatchObject({
      price_cents: 1550,
      audience: "group",
      open_to_non_members: false,
      guest_pass_allowed: false,
      guests_per_member: 0,
    });
    expect(eventRequest({ ...form, groupOnly: false }, { group: true })).toMatchObject({ audience: "open", open_to_non_members: true, guest_pass_allowed: true });
    expect(eventRequest({ ...form, groupOnly: false, openToAll: false }, { group: true }).audience).toBe("club");
    expect(eventRequest(form, { editing: true }).repeat_until).toBeUndefined();
  });

  it("makes a person's own event open or by invitation, never with guest passes", () => {
    expect(eventRequest(form, { mode: "self" })).toMatchObject({ audience: "open", open_to_non_members: true, guest_pass_allowed: false, guests_per_member: 0 });
    expect(eventRequest({ ...form, openToAll: false }, { mode: "self" })).toMatchObject({ audience: "club", open_to_non_members: false });
    expect(eventRequest({ ...form, groupOnly: true }, { mode: "self" }).audience).toBe("open");
  });

  it("picks the editor's mode: own, a member group's, else a club's", () => {
    expect(eventHostMode({ own: true, group: true })).toBe("self");
    expect(eventHostMode({ group: true })).toBe("group");
    expect(eventHostMode({})).toBe("club");
  });

  it("fills the form from an event for editing", () => {
    const filled = formFromEvent(event({ price_cents: 1500, capacity: null, guest_pass_allowed: true, guests_per_member: 2, good_for_friends: true }));
    expect(filled).toMatchObject({ paid: true, price: "15", capacity: "", guestPass: true, guestsPerMember: 2, goodForFriends: true, durationMinutes: 60 });
    expect(filled.place).toEqual({ kind: "location", locationId: "loc-1" });
  });
});

describe("eventErrorKey", () => {
  it("maps event error codes to their copy", () => {
    expect(eventErrorKey(new ApiError(409, "full", { code: "guest_limit_reached" }))).toBe("err_guest_limit_reached");
    expect(eventErrorKey(new ApiError(422, "nope", { code: "something_else" }))).toBeNull();
    expect(eventErrorKey(new Error("x"))).toBeNull();
  });
});

describe("patchEventIn", () => {
  it("replaces the event in lists, feed pages and a post's event, leaving the rest alone", () => {
    const patch = (entry: CommunityEvent) => ({ ...entry, going_count: 99 });
    const list = [event(), event({ id: "event-2" })];
    const patchedList = patchEventIn(list, "event-1", patch) as CommunityEvent[];
    expect(patchedList[0].going_count).toBe(99);
    expect(patchedList[1]).toBe(list[1]);

    const feed = { pages: [{ posts: [{ id: "post-1", event: event() }, { id: "post-2", event: null }], pinned: [] }], pageParams: [null] };
    const patchedFeed = patchEventIn(feed, "event-1", patch) as typeof feed;
    expect(patchedFeed.pages[0].posts[0].event?.going_count).toBe(99);
    expect(patchedFeed.pages[0].posts[1]).toBe(feed.pages[0].posts[1]);

    const untouched = { pages: [{ posts: [{ id: "post-3", event: null }] }] };
    expect(patchEventIn(untouched, "event-1", patch)).toBe(untouched);
  });
});
