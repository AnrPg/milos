import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { backSquat } from "./plan-view/plan-fixtures";
import { WorkoutPreviewDetail } from "./WorkoutPreviewDetail";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, values?: Record<string, unknown>) =>
    key === "supersetLabel" ? "Superset" :
    key === "setCount" ? `${values?.count} sets` :
    key === "value0Value1dca59cc" ? `${values?.value0} ${values?.value1}` : key,
}));

describe("WorkoutPreviewDetail composition groups", () => {
  it("shows the structured workout for free-text workouts that were parsed", () => {
    render(
      <WorkoutPreviewDetail
        authoringMode="free_text"
        freeTextBody={"AMRAP 20\n10 pull-ups"}
        sections={[{
          id: "section-1",
          name: "Main block",
          exercises: [{ id: "a", name: "Back squat", sets: 4, prescription_value: 6, prescription_unit: "reps" }],
        }]}
      />,
    );

    expect(screen.getByText("Main block")).toBeInTheDocument();
    expect(screen.getByText("Back squat")).toBeInTheDocument();
    expect(screen.queryByText(/AMRAP 20/)).not.toBeInTheDocument();
  });

  it("falls back to the free-text body when a free-text workout has no structure", () => {
    render(<WorkoutPreviewDetail authoringMode="free_text" freeTextBody={"AMRAP 20\n10 pull-ups"} sections={[]} />);

    expect(screen.getByText(/AMRAP 20/)).toBeInTheDocument();
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
              type: "paragraph",
              content: [{ type: "text", text: "Red zone", marks: [{ type: "textColor", attrs: { color: "#ef4444" } }] }],
            },
            {
              type: "paragraph",
              content: [{ type: "text", text: "Safe color", marks: [{ type: "textColor", attrs: { color: "javascript:red" } }] }],
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
    // The coach's colour, blended with the theme's text colour.
    expect(screen.getByText("Red zone").getAttribute("style") ?? "").toContain("#ef4444");
    expect(screen.getByText("Safe color")).not.toHaveAttribute("style");
    expect(screen.getByText("10 pull-ups").tagName).toBe("MARK");
    expect(screen.getByRole("list")).toBeInTheDocument();
  });

  it("shows each text section with its title, timer, scoring and the coach's formatting", () => {
    render(
      <WorkoutPreviewDetail
        authoringMode="sectioned_text"
        freeTextBody={"A\nBack squat 5x5\n\n21-15-9"}
        sections={[
          {
            id: "s1",
            name: "A",
            exercises: [],
            free_text_body: "Back squat 5x5",
            free_text_document: {
              type: "doc",
              content: [{ type: "paragraph", content: [{ type: "text", text: "Back squat 5x5", marks: [{ type: "underline" }] }] }],
            },
            timer_preset: { format: "emom", interval_seconds: 120, rounds: 5 },
            score_config: { metrics: [{ key: "load", label: "Load", kind: "load", unit: "kg" }] },
          },
          {
            id: "s2",
            name: "2",
            section_metadata: { untitled: true },
            exercises: [],
            free_text_body: "21-15-9",
            timer_preset: { format: "for_time", duration_seconds: 900 },
          },
        ]}
      />,
    );

    const sections = within(screen.getByRole("list", { name: "textSectionsPreviewLabel" })).getAllByRole("listitem");
    expect(sections).toHaveLength(2);
    expect(within(sections[0]).getByRole("heading", { name: "A" })).toBeInTheDocument();
    expect(within(sections[0]).getByText("Back squat 5x5").tagName).toBe("U");
    expect(within(sections[0]).getByText(/5 × 2:00/)).toBeInTheDocument();
    expect(within(sections[0]).getByText("textSectionScoredBy")).toBeInTheDocument();
    // An untitled section is named by its position, never by its stored number.
    expect(within(sections[1]).getByRole("heading", { name: "textSectionNumber" })).toBeInTheDocument();
    expect(within(sections[1]).getByText("21-15-9")).toBeInTheDocument();
    expect(screen.queryByText("freeTextPreviewEmpty")).not.toBeInTheDocument();
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

  it("shows a structured plan workout as its plan, not as its derived exercises", () => {
    render(
      <WorkoutPreviewDetail
        authoringMode="structured_plan"
        sections={[{
          id: "section-1",
          name: "Strength",
          plan: backSquat(),
          exercises: [{ id: "derived", name: "Derived squat row", sets: 4, prescription_value: 12, prescription_unit: "reps" }],
        }]}
      />,
    );

    const view = screen.getByTestId("plan-view");
    expect(within(view).getByText("Strength")).toBeInTheDocument();
    expect(within(view).getByText("Back Squat")).toBeInTheDocument();
    expect(within(view).getByTestId("plan-view-values")).toHaveTextContent("12-10-8-8 @ 60-65-70-75%");
    expect(screen.queryByText("Derived squat row")).not.toBeInTheDocument();
  });

  it("falls back to the derived exercises when a plan workout carries no readable plan", () => {
    render(
      <WorkoutPreviewDetail
        authoringMode="structured_plan"
        sections={[{ id: "section-1", name: "Strength", plan: { v: 99 }, exercises: [{ id: "derived", name: "Derived squat row" }] }]}
      />,
    );

    expect(screen.queryByTestId("plan-view")).not.toBeInTheDocument();
    expect(screen.getByText("Derived squat row")).toBeInTheDocument();
  });
});
