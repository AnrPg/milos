import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { SectionConfig } from "./SectionConfig";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));
vi.mock("./TimerTimeline", () => ({ TimerTimeline: () => null }));

/** Renders the selected section's settings the way LeftPanel does, from the live store. */
function SelectedSectionConfig() {
  const section = useWorkoutCreationStore((state) => state.sections[0]);
  return section ? <SectionConfig section={section} /> : <p>no section</p>;
}

function firstSection() {
  return useWorkoutCreationStore.getState().sections[0]!;
}

describe("SectionConfig (legacy structured canvas)", () => {
  beforeEach(() => {
    useWorkoutCreationStore.getState().resetDraft();
    useWorkoutCreationStore.getState().addSection();
  });

  it("renames and deletes the section", () => {
    render(<SelectedSectionConfig />);

    fireEvent.change(screen.getByPlaceholderText("eGMainSet8e9364b"), { target: { value: "Metcon" } });
    expect(firstSection().name).toBe("Metcon");

    fireEvent.click(screen.getByRole("button", { name: "deletef6fdbe4" }));
    expect(useWorkoutCreationStore.getState().sections).toHaveLength(0);
    expect(screen.getByText("no section")).toBeInTheDocument();
  });

  it("changes the format and edits an AMRAP's duration", () => {
    render(<SelectedSectionConfig />);

    fireEvent.click(screen.getByRole("button", { name: new RegExp(`^formatLabel_${firstSection().format}`) }));
    fireEvent.click(screen.getByRole("button", { name: "formatLabel_amrap" }));
    expect(firstSection().format).toBe("amrap");

    fireEvent.change(screen.getByRole("textbox", { name: "duration1370004" }), { target: { value: "15:00" } });
    expect(firstSection().formatParams.duration_seconds).toBe(900);
  });

  it("applies a section template", () => {
    render(<SelectedSectionConfig />);

    fireEvent.click(screen.getByRole("button", { name: "timerPreset_amrap12" }));
    expect(firstSection().format).toBe("amrap");
    expect(firstSection().formatParams.duration_seconds).toBe(720);
  });
});
