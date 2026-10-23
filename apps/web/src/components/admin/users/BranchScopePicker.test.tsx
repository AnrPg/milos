import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import type { FacilityLocation } from "@/api/facility";

import { BranchScopePicker } from "./BranchScopePicker";

const location = (id: string, name: string, archived = false): FacilityLocation => ({
  id,
  name,
  address: null,
  archived_at: archived ? "2026-10-01T00:00:00Z" : null,
});

const LOCATIONS = [location("k", "Κηφισιά"), location("m", "Μαρούσι"), location("g", "Γλυφάδα", true)];

function wrap(ui: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {ui}
    </NextIntlClientProvider>,
  );
}

describe("BranchScopePicker", () => {
  it("offers «All branches» and the active branches to someone who works everywhere", () => {
    const onChange = vi.fn();
    wrap(<BranchScopePicker locations={LOCATIONS} value="all" onChange={onChange} />);

    expect(screen.getByRole("button", { name: en.BranchScope.allBranches })).toHaveAttribute("aria-pressed", "true");
    expect(screen.queryByRole("button", { name: "Γλυφάδα" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Μαρούσι" }));
    expect(onChange).toHaveBeenCalledWith(["m"]);
  });

  it("adds and removes branches, and asks for one when none is left", () => {
    const onChange = vi.fn();
    const { rerender } = wrap(<BranchScopePicker locations={LOCATIONS} value={["k"]} onChange={onChange} />);

    fireEvent.click(screen.getByRole("button", { name: "Μαρούσι" }));
    expect(onChange).toHaveBeenLastCalledWith(["k", "m"]);
    fireEvent.click(screen.getByRole("button", { name: "Κηφισιά" }));
    expect(onChange).toHaveBeenLastCalledWith([]);

    rerender(
      <NextIntlClientProvider locale="en" messages={en}>
        <BranchScopePicker locations={LOCATIONS} value={[]} onChange={onChange} />
      </NextIntlClientProvider>,
    );
    expect(screen.getByText(en.BranchScope.chooseOneBranch)).toBeInTheDocument();
  });

  it("a branch manager hands out only their own branches, never «All branches»", () => {
    wrap(<BranchScopePicker locations={LOCATIONS} value={["k"]} allowed={["k"]} onChange={() => {}} />);

    expect(screen.queryByRole("button", { name: en.BranchScope.allBranches })).toBeNull();
    expect(screen.queryByRole("button", { name: "Μαρούσι" })).toBeNull();
    expect(screen.getByRole("button", { name: "Κηφισιά" })).toBeInTheDocument();
  });

  it("searches when the business has many branches", () => {
    const many = Array.from({ length: 10 }, (_, index) => location(`l${index}`, `Branch ${index}`));
    wrap(<BranchScopePicker locations={many} value="all" onChange={() => {}} />);

    fireEvent.change(screen.getByPlaceholderText(en.BranchScope.searchBranches), { target: { value: "Branch 7" } });
    expect(screen.getByRole("button", { name: "Branch 7" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Branch 3" })).toBeNull();
  });
});
