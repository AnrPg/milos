import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { useState } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { CollapsibleFilterBar } from "./CollapsibleFilterBar";
import { SegmentPicker, type SegmentOption } from "./SegmentPicker";
import { chooseValue } from "@/components/ui/select-test-utils";

function withIntl(ui: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {ui}
    </NextIntlClientProvider>,
  );
}

const ROLES: SegmentOption<string>[] = [
  { value: "all", label: "Everyone", count: 4 },
  { value: "member", label: "Members", count: 2 },
  { value: "athlete", label: "Athletes", count: 1 },
  { value: "admin", label: "Staff", count: 1 },
];

function Picker({ options = ROLES, stretch = false }: { options?: SegmentOption<string>[]; stretch?: boolean }) {
  const [value, setValue] = useState(options[0].value);
  return <SegmentPicker ariaLabel="Role" value={value} onChange={setValue} options={options} stretch={stretch} />;
}

const SEGMENTS: SegmentOption<string>[] = [
  { value: "plan", label: "Plan" },
  { value: "transactions", label: "Transactions" },
  { value: "offers", label: "Offers" },
];

/** jsdom has no layout: give every element a width so the picker can measure. */
function fakeLayout({ container, chip }: { container: number; chip: number }) {
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(container);
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(chip);
}

afterEach(() => vi.restoreAllMocks());

describe("SegmentPicker", () => {
  it("shows one row when every chip fits", () => {
    fakeLayout({ container: 600, chip: 100 });
    render(<Picker />);
    const tabs = screen.getAllByRole("tab");
    expect(tabs).toHaveLength(4);
    expect(screen.getByRole("tablist").className).not.toContain("grid");
  });

  it("uses a 2×2 grid for four chips that do not fit on a row", () => {
    fakeLayout({ container: 300, chip: 120 });
    render(<Picker />);
    const list = screen.getByRole("tablist");
    expect(list.className).toContain("grid");
    expect(list.style.gridTemplateColumns).toBe("repeat(2, minmax(0, 1fr))");
  });

  it("falls back to a dropdown when no grid is full", () => {
    fakeLayout({ container: 300, chip: 120 });
    render(<Picker options={ROLES.slice(0, 3)} />);
    expect(screen.queryByRole("tablist")).toBeNull();
    const select = screen.getByRole("combobox", { name: "Role" });
    // The folded tabs stand out: a Dojo fill and a chevron in its contrast colour.
    expect(select.style.background).toBe("var(--primary)");
    expect(select.style.color).toBe("var(--primary-contrast)");
    expect(select.style.getPropertyValue("--select-chevron")).toBe("var(--primary-contrast)");
    fireEvent.click(select);
    expect(screen.getByRole("option", { name: "Members (2)" })).toBeTruthy();
    fireEvent.click(select);
    chooseValue(select, "athlete");
    expect(select).toHaveAttribute("data-value", "athlete");
  });

  it("stretches chips equally when the widest fits every share", () => {
    fakeLayout({ container: 400, chip: 120 });
    render(<Picker options={SEGMENTS} stretch />);
    for (const tab of screen.getAllByRole("tab")) expect(tab.className).toContain("flex-1");
  });

  it("keeps natural widths on a stretched row that an equal share would cut", () => {
    // 70 + 120 + 70 + gaps fits 300px, three shares of 120 do not.
    vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(300);
    vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockImplementation(function (this: HTMLElement) {
      return this.textContent === "Transactions" ? 120 : 70;
    });
    render(<Picker options={SEGMENTS} stretch />);
    const tabs = screen.getAllByRole("tab");
    expect(tabs).toHaveLength(3);
    for (const tab of tabs) {
      expect(tab.className).toContain("flex-auto");
      expect(tab.className).not.toContain("flex-1");
    }
  });

  it("moves the selection with the arrow keys", () => {
    fakeLayout({ container: 600, chip: 100 });
    render(<Picker />);
    const first = screen.getByRole("tab", { name: /Everyone/ });
    expect(first.getAttribute("tabindex")).toBe("0");
    fireEvent.keyDown(first, { key: "ArrowRight" });
    expect(screen.getByRole("tab", { name: /Members/ }).getAttribute("aria-selected")).toBe("true");
    fireEvent.keyDown(screen.getByRole("tab", { name: /Members/ }), { key: "End" });
    expect(screen.getByRole("tab", { name: /Staff/ }).getAttribute("aria-selected")).toBe("true");
  });
});

describe("CollapsibleFilterBar", () => {
  it("shows only the search and the filter button until the button is pressed", () => {
    const onChange = vi.fn();
    withIntl(
      <CollapsibleFilterBar
        ariaLabel="Filters"
        search={{ value: "", onChange, placeholder: "Search by name", ariaLabel: "Search people" }}
        activeCount={2}
      >
        <label>
          Sort
          <select defaultValue="name">
            <option value="name">Name</option>
          </select>
        </label>
      </CollapsibleFilterBar>,
    );

    fireEvent.change(screen.getByRole("searchbox", { name: "Search people" }), { target: { value: "ann" } });
    expect(onChange).toHaveBeenCalledWith("ann");

    const toggle = screen.getByRole("button", { name: "Filters (2)" });
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    expect(screen.queryByRole("combobox", { name: "Sort" })).toBeNull();

    fireEvent.click(toggle);
    expect(toggle.getAttribute("aria-expanded")).toBe("true");
    expect(screen.getByRole("combobox", { name: "Sort" })).toBeTruthy();
  });

  it("offers clearing inside the open form while filters are on", () => {
    const onClear = vi.fn();
    withIntl(
      <CollapsibleFilterBar ariaLabel="Schedule filters" activeCount={1} onClear={onClear} defaultOpen>
        <span>chips</span>
      </CollapsibleFilterBar>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Clear all filters" }));
    expect(onClear).toHaveBeenCalled();
  });
});
