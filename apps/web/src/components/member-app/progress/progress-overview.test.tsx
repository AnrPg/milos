import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { ProgressOverview } from "./ProgressOverview";

const gamification = {
  stats: {
    perseverance_score: 92,
    total_workouts: 45,
    total_prs: 3,
    longest_streak: 4,
    advancement_count: 0,
  },
  level: {
    level: 7,
    xp: 3_340,
    level_start_xp: 3_300,
    next_level_xp: 4_100,
    points: { workouts: 50, prs: 100, weeks_on_goal: 150, challenges: 300 },
  },
  next_milestone: { badge_key: "workouts_50", kind: "workouts", current: 45, target: 50, remaining: 5 },
  strength: {
    percent: 6.4,
    window_days: 56,
    lifts: [{ name: "Back squat", from_kg: 100, to_kg: 108, gain_kg: 8 }],
    compared_lifts: 2,
    new_lifts: 0,
  } as Record<string, unknown> | null,
  goal: { weekly_workout_target: 3 },
  badges: [],
  preferences: { off_days: [] },
};

vi.mock("./use-landing", () => ({
  useLanding: () => ({ noGym: false, isPending: false, isError: false, data: { gamification } }),
}));

function renderOverview() {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      <ProgressOverview />
    </NextIntlClientProvider>,
  );
}

function card(label: string) {
  return screen.getByText(label).closest("article")!;
}

function openHelp(label: string) {
  fireEvent.click(within(card(label)).getByRole("button"));
  return screen.getByRole("dialog");
}

describe("ProgressOverview scores (ADR-285)", () => {
  beforeEach(() => {
    gamification.strength = {
      percent: 6.4,
      window_days: 56,
      lifts: [{ name: "Back squat", from_kg: 100, to_kg: 108, gain_kg: 8 }],
      compared_lifts: 2,
      new_lifts: 0,
    };
  });

  it("replaces Motivation with XP level, strength gain and the next milestone", () => {
    renderOverview();
    expect(screen.queryByText("Motivation")).toBeNull();

    const level = card(en.Ui.scoreLevel);
    expect(level.textContent).toContain("7");
    expect(level.textContent).toContain("3,340 / 4,100 XP to level 8");
    expect(within(level).getByRole("progressbar").getAttribute("aria-valuenow")).toBe("40");

    const strength = card(en.Ui.scoreStrength);
    expect(strength.textContent).toContain("+6.4%");
    expect(within(strength).getByRole("list").textContent).toContain("Back squat");
    expect(within(strength).getByRole("list").textContent).toContain("+8 kg");

    const milestone = card(en.Ui.scoreNextMilestone);
    expect(milestone.textContent).toContain("5");
    expect(milestone.textContent).toContain("workouts to the 50 workouts badge");
  });

  it("hides strength gain when no lift can be compared", () => {
    gamification.strength = null;
    renderOverview();
    expect(screen.queryByText(en.Ui.scoreStrength)).toBeNull();
    expect(screen.getByText(en.Ui.scoreLevel)).toBeTruthy();
  });

  it("each score opens its own explainer", () => {
    renderOverview();
    let dialog = openHelp(en.Ui.scoreLevel);
    expect(within(dialog).getByRole("heading", { name: en.Ui.scoreLevel })).toBeTruthy();
    expect(dialog.textContent).toContain("a workout +50, a PR +100, a week on your weekly goal +150");
    fireEvent.keyDown(document, { key: "Escape" });

    dialog = openHelp(en.Ui.scoreStrength);
    expect(dialog.textContent).toContain(en.Ui.scoreStrengthHelpWhat);
    fireEvent.keyDown(document, { key: "Escape" });

    dialog = openHelp(en.Ui.scoreNextMilestone);
    expect(dialog.textContent).toContain(en.Ui.scoreNextMilestoneHelpWhat);
    fireEvent.keyDown(document, { key: "Escape" });

    dialog = openHelp(en.Ui.perseverance3b53f48);
    expect(within(dialog).getByRole("heading", { name: en.Ui.perseverance3b53f48 })).toBeTruthy();
    expect(dialog.textContent).toContain(en.Ui.perseveranceHelpWhat);
  });
});
