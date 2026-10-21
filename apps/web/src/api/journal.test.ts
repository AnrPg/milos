import { afterEach, describe, expect, it, vi } from "vitest";

import { fetchJournalPage } from "@/api/journal";

describe("fetchJournalPage", () => {
  afterEach(() => vi.restoreAllMocks());

  it("sends a date range with the member's time zone (ADR-162)", async () => {
    vi.spyOn(Intl.DateTimeFormat.prototype, "resolvedOptions").mockReturnValue({
      timeZone: "Europe/Athens",
    } as Intl.ResolvedDateTimeFormatOptions);
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ items: [] }), { status: 200 }),
    );

    await fetchJournalPage("token", { filter: { date_from: "2026-10-01", q: "tempo" } });
    const dated = new URL(String(fetchMock.mock.calls[0][0]), "http://x");
    expect(dated.pathname).toBe("/api/me/journal");
    expect(dated.searchParams.get("date_from")).toBe("2026-10-01");
    expect(dated.searchParams.get("timezone")).toBe("Europe/Athens");

    await fetchJournalPage("token", { filter: { q: "tempo" } });
    const undated = new URL(String(fetchMock.mock.calls[1][0]), "http://x");
    expect(undated.searchParams.has("timezone")).toBe(false);
  });
});
