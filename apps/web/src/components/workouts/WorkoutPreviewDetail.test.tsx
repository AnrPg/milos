import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { WorkoutPreviewDetail } from "./WorkoutPreviewDetail";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, values?: Record<string, unknown>) =>
    key === "supersetLabel" ? "Superset" :
    key === "setsd6c8220" ? "sets" :
    key === "value0Value1dca59cc" ? `${values?.value0} ${values?.value1}` : key,
}));

describe("WorkoutPreviewDetail composition groups", () => {
  it("renders only the stored free-text body for free-text workouts", () => {
    render(
      <WorkoutPreviewDetail
        authoringMode="free_text"
        freeTextBody={"AMRAP 20\n10 pull-ups"}
        sections={[{
          id: "section-1",
          name: "Should not show",
          exercises: [{ id: "a", name: "Hidden squat", sets: 4, prescription_value: 6, prescription_unit: "reps" }],
        }]}
      />,
    );

    expect(screen.getByText(/AMRAP 20/)).toBeInTheDocument();
    expect(screen.queryByText("Should not show")).not.toBeInTheDocument();
    expect(screen.queryByText("Hidden squat")).not.toBeInTheDocument();
  });

  it("preserves rich free-text document formatting", () => {
    render(
      <WorkoutPreviewDetail
        authoringMode="free_text"
        freeTextBody="AMRAP 20"
        freeTextDocument={{
          type: "doc",
          content: [
            {
              type: "paragraph",
              attrs: { textAlign: "center" },
              content: [{ type: "text", text: "AMRAP 20", marks: [{ type: "bold" }] }],
            },
            {
              type: "orderedList",
              content: [
                {
                  type: "listItem",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "10 pull-ups", marks: [{ type: "highlight" }] }] }],
                },
              ],
            },
          ],
        }}
        sections={[]}
      />,
    );

    expect(screen.getByText("AMRAP 20").tagName).toBe("STRONG");
    expect(screen.getByText("AMRAP 20").closest("p")).toHaveStyle({ textAlign: "center" });
    expect(screen.getByText("10 pull-ups").tagName).toBe("MARK");
    expect(screen.getByRole("list")).toBeInTheDocument();
  });

  it("renders one group header with set count and child exercises without repeated group labels", () => {
    render(
      <WorkoutPreviewDetail
        sections={[{
          id: "section-1",
          name: "Strength",
          exercises: [
            { id: "a", name: "Squat", sets: 4, prescription_value: 6, prescription_unit: "reps", superset_group_id: "g1" },
            { id: "b", name: "Pull-up", sets: 4, prescription_value: 8, prescription_unit: "reps", superset_group_id: "g1" },
          ],
        }]}
      />,
    );

    const group = screen.getByRole("group", { name: /Superset.*4 sets/i });
    expect(within(group).getAllByText("Superset")).toHaveLength(1);
    expect(within(group).getByText("Squat")).toBeInTheDocument();
    expect(within(group).getByText("Pull-up")).toBeInTheDocument();
  });
});
