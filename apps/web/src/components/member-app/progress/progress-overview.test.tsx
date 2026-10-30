import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { ProgressOverview } from "./ProgressOverview";

vi.mock("./use-landing", () => ({
  useLanding: () => ({
    noGym: false,
    isPending: false,
    isError: false,
    data: {
      gamification: {
        stats: {
          motivation_score: 40,
          perseverance_score: 92,
          total_workouts: 0,
          total_prs: 0,
          longest_streak: 0,
          advancement_count: 0,
        },
        goal: { weekly_workout_target: 4 },
        badges: [],
        preferences: { off_days: [] },
      },
    },
  }),
}));

function renderOverview() {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      <ProgressOverview />
    </NextIntlClientProvider>,
  );
}

function openHelp(card: string) {
  const label = screen.getByText(card);
  fireEvent.click(within(label.closest("article")!).getByRole("button"));
  return screen.getByRole("dialog");
}

describe("ProgressOverview score help (ANR 2026-10-30)", () => {
  it("explains Motivation as weeks on the person's weekly goal", () => {
    renderOverview();
    const dialog = openHelp(en.Ui.motivationd6a0619);
    expect(within(dialog).getByRole("heading", { name: en.Ui.motivationd6a0619 })).toBeTruthy();
    expect(dialog.textContent).toContain("last 10 weeks");
    expect(dialog.textContent).toContain("4 workouts");
    expect(dialog.textContent).not.toContain(en.Ui.perseveranceHelpWhat);
  });

  it("explains Perseverance as following the prescription, not as a consistency score", () => {
    renderOverview();
    const dialog = openHelp(en.Ui.perseverance3b53f48);
    expect(within(dialog).getByRole("heading", { name: en.Ui.perseverance3b53f48 })).toBeTruthy();
    expect(dialog.textContent).toContain(en.Ui.perseveranceHelpWhat);
    expect(dialog.textContent).not.toContain("last 10 weeks");
  });
});
