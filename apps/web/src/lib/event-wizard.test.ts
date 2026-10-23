import { describe, expect, it } from "vitest";

import type { EventForm } from "@/components/events/events";

import {
  activeSteps,
  asksCohosts,
  asksGoodForFriends,
  asksGuestPass,
  canVisit,
  cohostInputProblem,
  draftFromState,
  draftWorthKeeping,
  eventWizardDraftKey,
  eventWizardReducer,
  firstInvalidStep,
  initialWizardState,
  MAX_COHOSTS,
  normalizeCohostSlug,
  parseEventWizardDraft,
  stepForField,
  stepProblems,
  type EventWizardContext,
  type EventWizardState,
} from "./event-wizard";

const NOW = new Date("2026-10-20T09:00:00Z");

const blank: EventForm = {
  title: "",
  description: "",
  date: "2026-10-24",
  time: "10:00",
  durationMinutes: 60,
  place: { kind: "address", name: "", address: "" },
  capacity: "",
  paid: false,
  price: "",
  openToAll: false,
  guestPass: false,
  guestsPerMember: 1,
  goodForFriends: false,
  repeatWeekly: false,
  repeatUntil: "",
  coverMediaId: null,
  timeZone: null,
  groupOnly: true,
};

const filled: EventForm = { ...blank, title: "Partner WOD", place: { kind: "location", locationId: "loc-1" } };

const context = (overrides: Partial<EventWizardContext> = {}): EventWizardContext => ({
  mode: "club",
  editing: false,
  hostChoices: 1,
  clubChoices: 1,
  cohostsAtCreate: false,
  gymTimeZone: "Europe/Athens",
  locationIds: ["loc-1", "loc-2"],
  ...overrides,
});

function run(state: EventWizardState, ...actions: Parameters<typeof eventWizardReducer>[1][]) {
  return actions.reduce(eventWizardReducer, state);
}

describe("event wizard steps", () => {
  it("asks for the host only when there is a choice, and never while editing", () => {
    expect(activeSteps(context())).toEqual(["basics", "when", "where", "who", "capacity", "review"]);
    expect(activeSteps(context({ hostChoices: 2 }))[0]).toBe("host");
    expect(activeSteps(context({ clubChoices: 3 }))[0]).toBe("host");
    expect(activeSteps(context({ hostChoices: 2, editing: true }))[0]).toBe("basics");
  });

  it("maps every field to the step that edits it", () => {
    expect(stepForField("title")).toBe("basics");
    expect(stepForField("timeZone")).toBe("when");
    expect(stepForField("place")).toBe("where");
    expect(stepForField("guestPass")).toBe("who");
    expect(stepForField("cohosts")).toBe("capacity");
    expect(stepForField("club")).toBe("host");
  });

  it("asks guest passes, good for friends and co-hosts only where they apply", () => {
    expect(asksGuestPass(blank, "self")).toBe(false);
    expect(asksGuestPass({ ...blank, groupOnly: true }, "group")).toBe(false);
    expect(asksGuestPass({ ...blank, groupOnly: false }, "group")).toBe(true);
    expect(asksGuestPass(blank, "club")).toBe(true);
    expect(asksGoodForFriends(blank, "club")).toBe(false);
    expect(asksGoodForFriends({ ...blank, guestPass: true }, "club")).toBe(true);
    expect(asksGoodForFriends({ ...blank, openToAll: true }, "self")).toBe(true);
    expect(asksCohosts(blank, context({ cohostsAtCreate: true }))).toBe(true);
    expect(asksCohosts(blank, context({ cohostsAtCreate: true, editing: true }))).toBe(false);
    expect(asksCohosts(blank, context({ cohostsAtCreate: true, mode: "self" }))).toBe(false);
    expect(asksCohosts({ ...blank, groupOnly: true }, context({ cohostsAtCreate: true, mode: "group" }))).toBe(false);
    expect(asksCohosts(blank, context())).toBe(false);
  });
});

describe("event wizard validation", () => {
  it("gives each step only its own problems, and the review all of them", () => {
    const form: EventForm = { ...blank, paid: true, capacity: "0" };
    expect(stepProblems("basics", form, context(), NOW)).toEqual(["title"]);
    expect(stepProblems("when", form, context(), NOW)).toEqual([]);
    expect(stepProblems("where", form, context(), NOW)).toEqual(["place"]);
    expect(stepProblems("who", form, context(), NOW)).toEqual(["price"]);
    expect(stepProblems("capacity", form, context(), NOW)).toEqual(["capacity"]);
    expect(stepProblems("review", form, context(), NOW)).toEqual(["title", "place", "capacity", "price"]);
    expect(firstInvalidStep(form, context(), NOW)).toBe("basics");
    expect(firstInvalidStep(filled, context(), NOW)).toBeNull();
  });

  it("reads the date on the gym's clock when the event has no zone of its own", () => {
    // 12:00 in Athens on 20 Oct is 09:00 UTC: exactly now, so it has passed.
    const noon = { ...filled, date: "2026-10-20", time: "12:00" };
    expect(stepProblems("when", noon, context(), NOW)).toEqual(["past"]);
    expect(stepProblems("when", { ...noon, timeZone: "America/New_York" }, context(), NOW)).toEqual([]);
    expect(stepProblems("when", noon, context({ editing: true }), NOW)).toEqual([]);
  });

  it("wants a repeat end from the first day on, and only when creating", () => {
    const weekly = { ...filled, repeatWeekly: true, repeatUntil: "2026-10-01" };
    expect(stepProblems("when", weekly, context(), NOW)).toEqual(["repeat"]);
    expect(stepProblems("when", { ...weekly, repeatUntil: "2026-12-01" }, context(), NOW)).toEqual([]);
    expect(stepProblems("when", weekly, context({ editing: true }), NOW)).toEqual([]);
  });

  it("rejects a branch the box no longer has, once its branches are known", () => {
    const gone = { ...filled, place: { kind: "location" as const, locationId: "loc-9" } };
    expect(stepProblems("where", gone, context(), NOW)).toEqual(["place"]);
    expect(stepProblems("where", gone, context({ locationIds: null }), NOW)).toEqual([]);
    expect(stepProblems("where", gone, context({ editing: true }), NOW)).toEqual([]);
  });
});

describe("event wizard state", () => {
  it("starts on the first step to create, and on the review (or a field's step) to edit", () => {
    expect(initialWizardState(blank, context({ hostChoices: 2 })).step).toBe("host");
    const edit = initialWizardState(filled, context({ editing: true }));
    expect(edit.step).toBe("review");
    expect(edit.visited).toEqual(activeSteps(context({ editing: true })));
    const onPlace = initialWizardState(filled, context({ editing: true }), { startStep: "where" });
    expect(onPlace).toMatchObject({ step: "where", returnToReview: true });
  });

  it("moves on only once the step is valid, and back without checks", () => {
    const ctx = context();
    let state = initialWizardState(blank, ctx);
    state = run(state, { type: "next", context: ctx, now: NOW });
    expect(state.step).toBe("basics");
    state = run(state, { type: "set", patch: { title: "Run" } }, { type: "next", context: ctx, now: NOW });
    expect(state.step).toBe("when");
    expect(state.visited).toEqual(["basics", "when"]);
    state = run(state, { type: "back", context: ctx });
    expect(state.step).toBe("basics");
    expect(run(state, { type: "back", context: ctx }).step).toBe("basics");
  });

  it("lets the step bar jump only to visited steps, and the review's «Edit» come back to it", () => {
    const ctx = context();
    let state = initialWizardState({ ...filled }, ctx);
    expect(canVisit(state, "who", ctx)).toBe(false);
    expect(run(state, { type: "goto", step: "who", context: ctx }).step).toBe("basics");
    for (let index = 0; index < 5; index += 1) state = run(state, { type: "next", context: ctx, now: NOW });
    expect(state.step).toBe("review");
    state = run(state, { type: "goto", step: "when", context: ctx });
    expect(state).toMatchObject({ step: "when", returnToReview: true });
    state = run(state, { type: "next", context: ctx, now: NOW });
    expect(state).toMatchObject({ step: "review", returnToReview: false });
  });

  it("leaves a step that drops away for the next one", () => {
    const withHost = context({ hostChoices: 2 });
    const state = initialWizardState(blank, withHost);
    expect(state.step).toBe("host");
    expect(run(state, { type: "back", context: context() }).step).toBe("basics");
  });

  it("sets the audience default for a new host until they choose one", () => {
    const state = initialWizardState(blank, context());
    expect(run(state, { type: "modeChanged", mode: "self" }).form.openToAll).toBe(true);
    const chosen = run(state, { type: "set", patch: { openToAll: false } }, { type: "modeChanged", mode: "self" });
    expect(chosen.form.openToAll).toBe(false);
  });

  it("drops another host's branch when switching to «Ως εγώ» or to a box without it", () => {
    const state = run(initialWizardState(filled, context()), { type: "set", patch: { place: { kind: "location", locationId: "loc-1" } } });
    expect(run(state, { type: "modeChanged", mode: "self" }).form.place).toEqual({ kind: "address", name: "", address: "" });
    expect(run(state, { type: "locationsArrived", locationIds: ["other"], editing: false }).form.place).toEqual({ kind: "location", locationId: "other" });
  });

  it("puts the event at the box's first branch once the branches load, unless they chose a place", () => {
    const state = initialWizardState(blank, context());
    const arrived = run(state, { type: "locationsArrived", locationIds: ["loc-1"], editing: false });
    expect(arrived.form.place).toEqual({ kind: "location", locationId: "loc-1" });
    const gone = run(arrived, { type: "locationsArrived", locationIds: ["loc-2"], editing: false });
    expect(gone.form.place).toEqual({ kind: "location", locationId: "loc-2" });
    const typed = run(state, { type: "set", patch: { place: { kind: "address", name: "", address: "" } } }, { type: "locationsArrived", locationIds: ["loc-1"], editing: false });
    expect(typed.form.place.kind).toBe("address");
    const editing = run(state, { type: "locationsArrived", locationIds: ["loc-1"], editing: true });
    expect(editing.form.place.kind).toBe("address");
  });

  it("keeps a clean, unique list of co-hosts up to the limit", () => {
    let state = initialWizardState(blank, context({ cohostsAtCreate: true }));
    state = run(
      state,
      { type: "addCohost", raw: "https://palee.app/b/Box-Kypseli/" },
      { type: "addCohost", raw: "box-kypseli" },
      { type: "addCohost", raw: "not a slug" },
      { type: "addCohost", raw: "my-gym", ownSlug: "my-gym" },
    );
    expect(state.cohosts).toEqual(["box-kypseli"]);
    expect(run(state, { type: "removeCohost", slug: "box-kypseli" }).cohosts).toEqual([]);
    const full = Array.from({ length: MAX_COHOSTS }, (_, index) => `box-${index}`);
    expect(cohostInputProblem("one-more", full)).toBe("cohost_limit");
  });
});

describe("co-host addresses", () => {
  it("reads a page address however it was pasted", () => {
    expect(normalizeCohostSlug(" box-kypseli ")).toBe("box-kypseli");
    expect(normalizeCohostSlug("/b/box-kypseli")).toBe("box-kypseli");
    expect(normalizeCohostSlug("https://palee.app/b/box-kypseli?ref=x")).toBe("box-kypseli");
    expect(normalizeCohostSlug("")).toBeNull();
    expect(normalizeCohostSlug("two words")).toBeNull();
    expect(normalizeCohostSlug("-dash")).toBeNull();
  });

  it("says why an address cannot be added", () => {
    expect(cohostInputProblem("?", [])).toBe("cohost_format");
    expect(cohostInputProblem("a-box", ["a-box"])).toBe("cohost_duplicate");
    expect(cohostInputProblem("MINE", [], "mine")).toBe("cohost_self");
    expect(cohostInputProblem("b-box", ["a-box"])).toBeNull();
  });
});

describe("event wizard drafts", () => {
  it("keeps a draft per host and reads it back", () => {
    expect(eventWizardDraftKey("hosted:self")).toBe("palee:event-wizard-draft:v1:hosted:self");
    const state = run(initialWizardState(blank, context({ cohostsAtCreate: true })), { type: "set", patch: { title: "Run" } }, { type: "addCohost", raw: "a-box" });
    const raw = JSON.stringify(draftFromState(state, NOW));
    expect(parseEventWizardDraft(raw, NOW)).toMatchObject({ form: { title: "Run" }, step: "basics", cohosts: ["a-box"] });
  });

  it("drops a missing, broken, foreign or stale draft", () => {
    const draft = draftFromState(initialWizardState(blank, context()), NOW);
    expect(parseEventWizardDraft(null, NOW)).toBeNull();
    expect(parseEventWizardDraft("{", NOW)).toBeNull();
    expect(parseEventWizardDraft(JSON.stringify({ ...draft, version: 0 }), NOW)).toBeNull();
    expect(parseEventWizardDraft(JSON.stringify({ ...draft, form: { ...blank, title: 3 } }), NOW)).toBeNull();
    expect(parseEventWizardDraft(JSON.stringify({ ...draft, step: "nope" }), NOW)).toBeNull();
    const later = new Date(NOW.getTime() + 15 * 24 * 60 * 60 * 1000);
    expect(parseEventWizardDraft(JSON.stringify(draft), later)).toBeNull();
  });

  it("keeps a draft only once something was changed from the blank form", () => {
    const state = initialWizardState(blank, context());
    expect(draftWorthKeeping(state, blank)).toBe(false);
    // The branch default arriving late is not a change of theirs.
    expect(draftWorthKeeping(run(state, { type: "locationsArrived", locationIds: ["loc-1"], editing: false }), blank)).toBe(false);
    expect(draftWorthKeeping(run(state, { type: "set", patch: { title: "Run" } }), blank)).toBe(true);
    expect(draftWorthKeeping(run(state, { type: "set", patch: { durationMinutes: 90 } }), blank)).toBe(true);
  });

  it("restores a draft on a step this host has", () => {
    const ctx = context();
    const draft = { ...draftFromState(initialWizardState(filled, ctx), NOW), step: "host" as const, visited: ["host" as const] };
    const restored = run(initialWizardState(blank, ctx), { type: "restore", draft, context: ctx });
    expect(restored).toMatchObject({ step: "basics", form: { title: "Partner WOD" } });
    expect(restored.visited).toContain("basics");
  });
});
