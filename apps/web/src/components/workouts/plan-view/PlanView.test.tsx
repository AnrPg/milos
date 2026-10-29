import { render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../../messages/el.json";

import { amrapPerRound, backSquat, differentRounds, giantSet, interrupted, measured, tabata } from "./plan-fixtures";
import { PlanView, type PlanViewSource } from "./PlanView";

function renderView(sections: PlanViewSource[], levelLabels?: Record<string, string>) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      <PlanView sections={sections} levelLabels={levelLabels} />
    </NextIntlClientProvider>,
  );
}

describe("PlanView", () => {
  it("renders every section with its flow, parameters and exercises", () => {
    renderView([
      { id: "a", name: "Δευτέρα A", plan: backSquat() },
      { id: "b", name: "", plan: differentRounds() },
      { id: "c", name: "Finisher", plan: tabata() },
    ]);

    const view = screen.getByTestId("plan-view");
    const sections = within(view).getAllByTestId("plan-view-section");
    expect(sections).toHaveLength(3);
    expect(within(sections[0]!).getByText("Δευτέρα A")).toBeInTheDocument();
    expect(within(sections[0]!).getByTestId("plan-view-flow")).toHaveTextContent("Σετ");
    expect(within(sections[0]!).getByTestId("plan-view-params")).toHaveTextContent("4 σετ · 2′ ξεκούραση");
    expect(within(sections[0]!).getByTestId("plan-view-values")).toHaveTextContent("12-10-8-8 @ 60-65-70-75%");
    expect(within(sections[0]!).getByText("Tempo ↓3 ·1 ↑X ·1")).toBeInTheDocument();

    // An untitled section gets its letter; different rounds are labelled.
    expect(within(sections[1]!).getByText("Ενότητα B")).toBeInTheDocument();
    expect(within(sections[1]!).getAllByTestId("plan-view-block-label").map((label) => label.textContent)).toEqual(["Γύρος 1, 3, 5", "Γύρος 2, 4, 6"]);

    expect(within(sections[2]!).getByTestId("plan-view-flow")).toHaveTextContent("Intervals");
    expect(within(sections[2]!).getByText("Tabata")).toBeInTheDocument();
  });

  it("shows structures, per side, measures, interruptions and notes", () => {
    renderView(
      [
        { id: "g", name: "Giant", plan: giantSet() },
        { id: "m", name: "Accessory", plan: measured() },
        { id: "i", name: "Thrusters", plan: interrupted() },
        { id: "p", name: "AMRAP", plan: amrapPerRound() },
      ],
      { rx: "RX" },
    );

    expect(screen.getByTestId("plan-view-structure")).toHaveTextContent("Superset");
    expect(screen.getByText("ανά πλευρά")).toBeInTheDocument();
    expect(screen.getByText("Ύψος 60 cm")).toBeInTheDocument();
    expect(screen.getByText("Ξεκούραση")).toBeInTheDocument();
    expect(screen.getByText("Ήρεμα, τεχνική πρώτα")).toBeInTheDocument();
    expect(screen.getByText("RX")).toBeInTheDocument();
    expect(screen.getByText("Με γιλέκο 10 kg")).toBeInTheDocument();
    const lane = screen.getByTestId("plan-view-interrupt");
    expect(within(lane).getByText("Κάθε 2′ σταματάς για")).toBeInTheDocument();
    expect(within(lane).getByText("Burpee over Bar")).toBeInTheDocument();
    expect(screen.getByText("5-10-15 @ 40-45-50 kg…")).toBeInTheDocument();
  });

  it("says when nothing is written", () => {
    renderView([]);
    expect(screen.getByTestId("plan-view")).toHaveTextContent("Δεν έχει γραφτεί τίποτα ακόμα.");
  });
});
