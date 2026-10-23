import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { FacilityLocation } from "@/api/facility";

import { defaultAppliesTo, showsAppliesTo } from "./AppliesToBranches";
import { BranchFilterControl, BranchSplits, type BranchFilterState } from "./BranchFilter";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: null }) }));

const location = (id: string, name: string, archived = false): FacilityLocation => ({
  id,
  name,
  address: null,
  archived_at: archived ? "2026-10-01T00:00:00Z" : null,
});

const LOCATIONS = [location("k", "Κηφισιά"), location("m", "Μαρούσι")];

function wrap(ui: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {ui}
    </NextIntlClientProvider>,
  );
}

function state(selected: string[], setSelected = vi.fn(), locations = LOCATIONS): BranchFilterState {
  return { locations, selected, setSelected, param: selected.join(",") || undefined, visible: locations.length >= 2 };
}

describe("BranchFilterControl", () => {
  it("reads «Branches: All» and filters by the branches ticked in its checklist", () => {
    const setSelected = vi.fn();
    wrap(<BranchFilterControl filter={state([], setSelected)} />);

    const trigger = screen.getByRole("button", { name: /Branches:\s*All/ });
    fireEvent.click(trigger);

    expect(screen.getByRole("menuitemcheckbox", { name: en.BranchScope.allBranches })).toHaveAttribute("aria-checked", "true");
    fireEvent.click(screen.getByRole("menuitemcheckbox", { name: "Μαρούσι" }));
    expect(setSelected).toHaveBeenCalledWith(["m"]);
  });

  it("names the one branch shown, and goes back to all", () => {
    const setSelected = vi.fn();
    wrap(<BranchFilterControl filter={state(["k"], setSelected)} />);

    fireEvent.click(screen.getByRole("button", { name: /Κηφισιά/ }));
    fireEvent.click(screen.getByRole("menuitemcheckbox", { name: en.BranchScope.allBranches }));
    expect(setSelected).toHaveBeenCalledWith([]);
  });

  it("is hidden for someone who sees one branch", () => {
    const { container } = wrap(<BranchFilterControl filter={state([], vi.fn(), [LOCATIONS[0]])} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe("BranchSplits", () => {
  it("shows a row per branch only when two or more are shown", () => {
    const rows = [
      { location_id: "k", name: "Κηφισιά", active_memberships: 3 },
      { location_id: "m", name: "Μαρούσι", active_memberships: 1 },
    ];
    const { rerender } = wrap(<BranchSplits rows={rows} columns={[{ key: "active_memberships", label: "Active" }]} />);
    expect(screen.getByRole("cell", { name: "Κηφισιά" })).toBeInTheDocument();
    expect(screen.getByRole("cell", { name: "3" })).toBeInTheDocument();

    rerender(
      <NextIntlClientProvider locale="en" messages={en}>
        <BranchSplits rows={rows.slice(0, 1)} columns={[{ key: "active_memberships", label: "Active" }]} />
      </NextIntlClientProvider>,
    );
    expect(screen.queryByRole("table")).toBeNull();
  });
});

describe("«Applies to» defaults", () => {
  const withArchived = [...LOCATIONS, location("g", "Γλυφάδα", true)];

  it("shows only with two or more active branches", () => {
    expect(showsAppliesTo(withArchived)).toBe(true);
    expect(showsAppliesTo([LOCATIONS[0], location("g", "Γλυφάδα", true)])).toBe(false);
  });

  it("defaults to the page filter, else every branch offered", () => {
    expect(defaultAppliesTo(withArchived)).toEqual(["k", "m"]);
    expect(defaultAppliesTo(withArchived, ["m", "g"])).toEqual(["m"]);
    expect(defaultAppliesTo(withArchived, ["g"])).toEqual(["k", "m"]);
  });
});
