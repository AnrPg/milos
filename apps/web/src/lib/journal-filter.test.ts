import { describe, expect, it } from "vitest";

import { EMPTY_JOURNAL_FILTER } from "@/api/journal";
import {
  effectiveJournalFilter,
  journalFilterCount,
  journalFilterKey,
  parseJournalFilter,
  withKnownSources,
} from "@/lib/journal-filter";

describe("journal filter (ADR-162 JournalFilter v1)", () => {
  it("reads a remembered filter and drops what it does not know", () => {
    expect(
      parseJournalFilter({
        v: 1,
        kinds: ["execution", "selfie"],
        sources: ["org-1", "freeform"],
        visibilities: "private,shouted",
        date_from: "2026-10-01",
        date_to: "yesterday",
        q: "  fran ",
      }),
    ).toEqual({
      kinds: ["execution"],
      sources: ["org-1", "freeform"],
      visibilities: ["private"],
      date_from: "2026-10-01",
      date_to: null,
      q: "fran",
    });
  });

  it("refuses a filter from another version rather than half-reading it", () => {
    expect(parseJournalFilter({ v: 2, kinds: ["execution"] })).toEqual(EMPTY_JOURNAL_FILTER);
    expect(parseJournalFilter(null)).toEqual(EMPTY_JOURNAL_FILTER);
  });

  it("counts a date range once and ignores one-letter searches, like the server", () => {
    expect(journalFilterCount({ ...EMPTY_JOURNAL_FILTER, date_from: "2026-10-01", date_to: "2026-10-05" })).toBe(1);
    expect(journalFilterCount({ ...EMPTY_JOURNAL_FILTER, q: "a" })).toBe(0);
    expect(journalFilterCount({ ...EMPTY_JOURNAL_FILTER, kinds: ["pr"], sources: ["device"], q: "pr" })).toBe(3);
  });

  it("asks for the same feed whatever the order of picks", () => {
    const a = { ...EMPTY_JOURNAL_FILTER, sources: ["b", "a"], q: "x" };
    const b = { ...EMPTY_JOURNAL_FILTER, sources: ["a", "b"] };
    expect(journalFilterKey(a)).toBe(journalFilterKey(b));
    expect(effectiveJournalFilter(a).q).toBeNull();
  });

  it("drops sources that are gone", () => {
    const filter = { ...EMPTY_JOURNAL_FILTER, sources: ["org-1", "org-gone", "freeform"] };
    expect(withKnownSources(filter, new Set(["org-1", "freeform"])).sources).toEqual(["org-1", "freeform"]);
    expect(withKnownSources(filter, new Set(["org-1", "org-gone", "freeform"]))).toBe(filter);
  });
});
