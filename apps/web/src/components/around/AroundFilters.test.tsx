import { fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { DEFAULT_FILTER, type AroundFilter } from "./around";
import { AroundChipRow, RadiusChip } from "./AroundFilters";

const state = vi.hoisted(() => ({
  filter: null as unknown as AroundFilter,
  setFilter: vi.fn(),
  mine: [] as string[],
  saved: [] as Array<{ id: string; name: string; params: unknown; alert: boolean }>,
}));

vi.mock("./use-around", () => ({
  useAround: () => ({ filter: state.filter, setFilter: state.setFilter, saved: state.saved }),
  useAroundArea: () => ({ data: [], isPending: false }),
  useNeighbourhoodSearch: () => ({ data: [] }),
  useResolvePlace: () => ({ mutate: vi.fn(), isPending: false, error: null }),
  useSavedFilterActions: () => ({ save: {}, alert: {}, rename: {}, remove: {} }),
}));

vi.mock("@/components/interests/InterestsEditor", () => ({
  useMyInterests: () => ({ data: { disciplines: state.mine } }),
}));

vi.mock("@/api/public-profile", () => ({
  getBoxVocabulary: () => new Promise(() => {}),
}));

function renderRow(ui: React.ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <NextIntlClientProvider locale="en" messages={en}>
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

/** jsdom has no layout: give the row and every chip a width so it can measure. */
function fakeLayout({ container, chip }: { container: number; chip: number }) {
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(container);
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(chip);
}

beforeEach(() => {
  state.filter = DEFAULT_FILTER;
  state.setFilter = vi.fn();
  state.mine = [];
  state.saved = [];
});

afterEach(() => vi.restoreAllMocks());

describe("AroundChipRow", () => {
  it("shows only Filters, My sports, When and Free", () => {
    state.mine = ["hyrox"];
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    const row = screen.getByRole("toolbar", { name: en.Around.filtersLabel });
    const names = within(row)
      .getAllByRole("button")
      .map((button) => button.textContent?.replace("▾", "").trim());
    expect(names).toEqual(["Filters", "My sports", "When", "Free"]);
    expect(within(row).queryByRole("button", { name: "Trial" })).toBeNull();
    expect(within(row).queryByRole("button", { name: "Posts" })).toBeNull();
    expect(within(row).queryByText(/km/)).toBeNull();
  });

  it("leaves My sports out for someone without interests", () => {
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    expect(screen.queryByRole("button", { name: "My sports" })).toBeNull();
    expect(screen.getByRole("button", { name: "Free" })).toBeTruthy();
  });

  it("counts the facets that moved into the sheet in Filters (n)", () => {
    state.filter = { ...DEFAULT_FILTER, radius_km: 10, cost: ["trial"], kinds: [...DEFAULT_FILTER.kinds, "posts"], disciplines: ["yoga"] };
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    expect(screen.getByRole("button", { name: "Filters (4)" })).toBeTruthy();
  });

  it("stays on one line when it fits and breaks into two balanced lines when not, never scrolling", () => {
    state.mine = ["hyrox"];
    fakeLayout({ container: 600, chip: 90 });
    const { unmount } = renderRow(<AroundChipRow resultCount={3} />);
    let row = screen.getByRole("toolbar", { name: en.Around.filtersLabel });
    expect(row.children).toHaveLength(1);
    expect(row.className).not.toContain("overflow-x-auto");
    unmount();

    fakeLayout({ container: 288, chip: 110 });
    renderRow(<AroundChipRow resultCount={3} />);
    row = screen.getByRole("toolbar", { name: en.Around.filtersLabel });
    expect(row.children).toHaveLength(2);
    expect(Array.from(row.children).map((line) => line.children.length)).toEqual([2, 2]);
    expect(row.className).not.toContain("overflow-x-auto");
  });

  it("toggles My sports to the person's disciplines", () => {
    state.mine = ["hyrox", "yoga"];
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    fireEvent.click(screen.getByRole("button", { name: "My sports" }));
    expect(state.setFilter).toHaveBeenCalledWith({ ...DEFAULT_FILTER, disciplines: ["hyrox", "yoga"] });
  });

  it("keeps every option that left the row in the sheet, saved filters included", () => {
    state.saved = [{ id: "s1", name: "Weekend near home", params: { v: 1, when: "weekend" }, alert: false }];
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    expect(screen.queryByRole("button", { name: "Weekend near home" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Filters" }));
    expect(screen.getByRole("group", { name: en.Around.sectionSaved })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Weekend near home" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Trial" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Posts" })).toBeTruthy();
    expect(screen.getByRole("group", { name: en.Around.sectionDiscipline })).toBeTruthy();
    expect(screen.getByRole("slider", { name: en.Around.radius })).toBeTruthy();
  });

  it("puts date pickers above the When shortcuts and a price range above the Cost shortcuts", () => {
    state.filter = { ...DEFAULT_FILTER, when: "range", date_from: "2030-05-02", date_to: "2030-05-04" };
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    fireEvent.click(screen.getByRole("button", { name: "Filters (1)" }));

    const dates = screen.getByRole("group", { name: en.Around.dates });
    const from = within(dates).getByRole("button", { name: en.Around.dateFrom });
    expect(from.getAttribute("data-value")).toBe("2030-05-02");
    expect(within(dates).getByRole("button", { name: en.Around.dateTo }).getAttribute("data-value")).toBe("2030-05-04");
    const today = screen.getByRole("button", { name: en.Around.when_today });
    expect(dates.compareDocumentPosition(today) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();

    const lowest = screen.getByRole("slider", { name: en.Around.priceFrom });
    const free = screen.getAllByRole("button", { name: "Free" }).at(-1)!;
    expect(lowest.compareDocumentPosition(free) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    fireEvent.change(lowest, { target: { value: "500" } });
    expect(state.setFilter).toHaveBeenLastCalledWith({ ...state.filter, min_price_cents: 500, max_price_cents: null });
  });

  it("makes Free and Up to €15 shortcuts that replace each other", () => {
    state.filter = { ...DEFAULT_FILTER, cost: ["free"] };
    fakeLayout({ container: 600, chip: 90 });
    renderRow(<AroundChipRow resultCount={3} />);
    fireEvent.click(screen.getByRole("button", { name: "Filters (1)" }));
    fireEvent.click(screen.getByRole("button", { name: "Up to €15" }));
    expect(state.setFilter).toHaveBeenLastCalledWith({ ...DEFAULT_FILTER, max_price_cents: 1500 });
  });
});

describe("RadiusChip", () => {
  it("shows the radius and changes it from its menu", () => {
    renderRow(<RadiusChip />);
    fireEvent.click(screen.getByRole("button", { name: /≤ 3 km/ }));
    fireEvent.click(screen.getByRole("menuitemradio", { name: /≤ 10 km/ }));
    expect(state.setFilter).toHaveBeenCalledWith({ ...DEFAULT_FILTER, radius_km: 10 });
  });
});
