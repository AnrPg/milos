import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { SectionScoringField } from "./SectionScoringField";

const LABELS: Record<string, string> = {
  scoreKind_rounds: "Rounds",
  scoreKind_reps: "Reps",
  scoreKind_time: "Time",
  scoreKind_load: "Load (kg)",
  scoreKind_calories: "Calories",
  scoreKind_distance: "Distance (m)",
  scoreKind_custom: "Number",
};

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, values?: { number?: number }) =>
    LABELS[key] ?? (values?.number ? `${key} ${values.number}` : key),
}));

describe("SectionScoringField (ADR-180)", () => {
  it("picks one paradigm per field and adds more fields with +", () => {
    const onChange = vi.fn();
    render(<SectionScoringField metrics={[]} invalid={false} onChange={onChange} />);

    const add = screen.getByRole("button", { name: "addScoreMetric" });
    expect(add).toBeDisabled();

    fireEvent.focus(screen.getByRole("combobox", { name: "scoreFieldLabel 1" }));
    fireEvent.click(screen.getByRole("option", { name: "Reps" }));
    expect(onChange).toHaveBeenLastCalledWith([{ key: "reps", label: "Reps", kind: "reps" }]);

    fireEvent.click(add);
    const second = screen.getByRole("combobox", { name: "scoreFieldLabel 2" });
    fireEvent.change(second, { target: { value: "lo" } });
    const best = within(screen.getByRole("listbox")).getAllByRole("option")[0]!;
    expect(best).toHaveTextContent("Load (kg)");
    fireEvent.click(best);
    expect(onChange).toHaveBeenLastCalledWith([
      { key: "reps", label: "Reps", kind: "reps" },
      { key: "load-kg", label: "Load (kg)", kind: "load" },
    ]);

    // The same paradigm again (another part of the section) gets a number.
    fireEvent.click(add);
    fireEvent.focus(screen.getByRole("combobox", { name: "scoreFieldLabel 3" }));
    fireEvent.click(screen.getByRole("option", { name: "Reps" }));
    expect(onChange.mock.lastCall![0][2]).toEqual({ key: "reps-2", label: "Reps 2", kind: "reps" });

    fireEvent.click(screen.getByRole("button", { name: "removeScoreField 2" }));
    expect(onChange.mock.lastCall![0].map((metric: { label: string }) => metric.label)).toEqual(["Reps", "Reps 2"]);
  });

  it("keeps a name of the coach's own, counting what it guesses", () => {
    const onChange = vi.fn();
    render(<SectionScoringField metrics={[]} invalid={false} onChange={onChange} />);
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "Row calories" } });
    expect(onChange).toHaveBeenLastCalledWith([{ key: "row-calories", label: "Row calories", kind: "calories" }]);
    expect(screen.getByRole("combobox", { name: "scoreFieldLabel 1" })).toHaveValue("Row calories");
  });
});
