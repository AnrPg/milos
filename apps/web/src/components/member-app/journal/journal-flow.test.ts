import { describe, expect, it } from "vitest";

import type { JournalFeedItem, JournalFeedPage } from "@/api/journal";

import { journalFlow, withAudience, withVisibility } from "./journal-flow";

const item = (overrides: Partial<JournalFeedItem>): JournalFeedItem => ({
  kind: "note",
  id: "n1",
  occurred_at: "2026-10-15T16:00:00Z",
  occurred_tz: "Europe/Athens",
  occurred_on: null,
  organization_id: "gym",
  journal_visibility: "private",
  choosable_visibilities: ["private", "coach_can_view", "coach_reply_requested"],
  entry: {},
  ...overrides,
});

const page = (items: JournalFeedItem[], next_cursor: string | null = null): JournalFeedPage => ({ items, next_cursor });

describe("journalFlow", () => {
  it("groups the server's order by the day each entry happened, in its own zone", () => {
    const days = journalFlow([
      page([
        // 22:30 UTC is already the next day in Athens.
        item({ kind: "execution", id: "fran", occurred_at: "2026-10-15T22:30:00Z" }),
        item({ kind: "note", id: "n1", occurred_at: "2026-10-15T16:00:00Z" }),
      ]),
      page([item({ kind: "pr", id: "p1", occurred_at: "2026-10-14T00:00:00Z", occurred_tz: null, occurred_on: "2026-10-14" })]),
    ]);

    expect(days.map((day) => [day.day, day.items.map((entry) => entry.id)])).toEqual([
      ["2026-10-16", ["fran"]],
      ["2026-10-15", ["n1"]],
      ["2026-10-14", ["p1"]],
    ]);
  });

  it("shows an entry once even if two pages overlap", () => {
    const days = journalFlow([page([item({ id: "n1" })]), page([item({ id: "n1" })])]);
    expect(days.flatMap((day) => day.items)).toHaveLength(1);
  });
});

describe("withVisibility", () => {
  it("puts the server's new rung and choices on the moved entry only", () => {
    const pages = [page([item({ id: "n1" }), item({ id: "n2" })])];
    const [moved] = withVisibility(pages, {
      kind: "note",
      id: "n1",
      journal_visibility: "coach_reply_requested",
      choosable_visibilities: ["private", "coach_can_view", "coach_reply_requested"],
    });

    expect(moved.items.map((entry) => entry.journal_visibility)).toEqual(["coach_reply_requested", "private"]);
  });
});

describe("withAudience (ADR-162)", () => {
  it("sets one entry's coach audience and leaves the rest", () => {
    const pages = [page([item({ id: "a" }), item({ id: "b", audience: { custom: false, organization_ids: ["gym"], coaches: [] } })])];
    const next = withAudience(pages, { kind: "note", id: "a" }, { custom: true, organization_ids: ["coach"], coaches: [{ organization_id: "coach", user_id: "nikos" }] });
    expect(next[0].items[0].audience).toEqual({ custom: true, organization_ids: ["coach"], coaches: [{ organization_id: "coach", user_id: "nikos" }] });
    expect(next[0].items[1].audience).toEqual({ custom: false, organization_ids: ["gym"], coaches: [] });
  });
});
