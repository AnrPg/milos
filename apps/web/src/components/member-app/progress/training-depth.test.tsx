import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { CoachTrainingDepthPanel } from "./CoachTrainingDepthPanel";
import { ProgressDepthSections } from "./ProgressDepthSections";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

const qualities = [
  "cardiorespiratory-endurance",
  "stamina",
  "strength",
  "flexibility",
  "power",
  "speed",
  "coordination",
  "agility",
  "balance",
  "accuracy",
].map((id) => ({
  id,
  sets: id === "strength" ? 12 : id === "stamina" ? 6 : 0,
  score: id === "strength" ? 1 : id === "stamina" ? 0.5 : 0,
  felt: id === "strength" ? 2 : 0,
}));

const depth = {
  range: "12w",
  from: "2026-07-30",
  to: "2026-10-21",
  weeks: 12,
  sources: [],
  coverage: {
    sessions: 9,
    exercises: { recognized: 20, unrecognized: 1 },
    felt_entries: 2,
    thresholds: { medium: 3, high: 8 },
    most: [{ id: "quadriceps", sets: 40, per_week: 3.3, level: "medium" }],
    least: [{ id: "hamstrings", sets: 2, per_week: 0.2, level: "low" }],
    balance: { push: 14, pull: 10, push_pull_ratio: 1.4, quad: 30, ham: 3, quad_ham_ratio: null },
  },
  qualities: { sessions: 9, felt_entries: 2, qualities },
  load: {
    acute: 900,
    chronic: 600,
    ratio: 1.5,
    band: "above",
    sufficient: true,
    rated_sessions: 10,
    unrated_sessions: 2,
    bands: { below: 0.8, steady_to: 1.3, above_to: 1.5 },
    weeks: [
      { week_start: "2026-10-12", load: 600, sessions: 3 },
      { week_start: "2026-10-19", load: 900, sessions: 4 },
    ],
  },
};

function renderWith(node: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        {node}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("Πρόοδος depth sections (ADR-165)", () => {
  beforeEach(() => apiRequest.mockReset());

  it("shows coverage with atlas links, the radar and load as an indicator", async () => {
    apiRequest.mockResolvedValue(depth);
    renderWith(<ProgressDepthSections filter={{ range: "12w", sources: ["org-1"], exercise: "squat" }} />);

    await screen.findByText("1.4 : 1");
    const coverage = screen.getByRole("region", { name: "Muscle coverage" });
    expect(apiRequest).toHaveBeenCalledWith("/me/progress/depth?range=12w&sources=org-1", { token: "token", scope: "account" });
    expect(within(coverage).getByRole("link", { name: "Atlas ›" })).toHaveAttribute("href", "/journal/atlas");
    expect(within(coverage).getByRole("link", { name: /Quadriceps/ })).toHaveAttribute("href", "/journal/atlas?node=quadriceps");
    expect(within(coverage).getByRole("link", { name: /Hamstrings/ })).toHaveAttribute("href", "/journal/atlas?node=hamstrings");
    expect(within(coverage).getByText("1.4 : 1")).toBeInTheDocument();
    expect(within(coverage).getByText("A few more sets needed")).toBeInTheDocument();
    expect(within(coverage).getByText("An indication of training volume, not a target.")).toBeInTheDocument();

    const radar = screen.getByRole("region", { name: "Fitness qualities" });
    expect(within(radar).getByRole("img", { name: /Most: Strength, Stamina/ })).toBeInTheDocument();
    expect(within(radar).getByText("“Felt”: Strength")).toBeInTheDocument();

    const load = screen.getByRole("region", { name: "Training load" });
    expect(within(load).getByText("This week: 1.5× your usual")).toBeInTheDocument();
    expect(within(load).getByTestId("load-band")).toHaveTextContent("Above usual");
    expect(within(load).getByText(/2 workouts in the last 4 weeks have no RPE/)).toBeInTheDocument();
    expect(within(load).getByText(/not medical advice/)).toBeInTheDocument();
  });

  // ANR 2026-10-24 (PR #101): the member's Πρόοδος hides a card with nothing in it.
  it("hides every empty slot from the member, also for a {} answer", async () => {
    apiRequest.mockResolvedValue({});
    renderWith(<ProgressDepthSections filter={{ range: "4w", sources: [] }} />);
    await waitFor(() => expect(apiRequest).toHaveBeenCalled());
    await waitFor(() => expect(screen.queryByRole("region", { name: "Muscle coverage" })).toBeNull());
    expect(screen.queryByRole("region", { name: "Fitness qualities" })).toBeNull();
    expect(screen.queryByRole("region", { name: "Training load" })).toBeNull();
    expect(screen.queryByText("No workouts in this period.")).toBeNull();
  });

  it("keeps every slot for the coach with neutral empty states, also for a {} answer", async () => {
    apiRequest.mockResolvedValue({});
    renderWith(<CoachTrainingDepthPanel userId="u-1" />);
    expect(await screen.findAllByText("No workouts in this period.")).toHaveLength(3);
    expect(screen.getByRole("region", { name: "Muscle coverage" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Fitness qualities" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Training load" })).toBeInTheDocument();
  });

  it("asks for more weeks before comparing load, and the coach sees there is no data", async () => {
    const empty = {
      ...depth,
      coverage: { ...depth.coverage, sessions: 0, most: [], least: [] },
      qualities: { sessions: 0, felt_entries: 0, qualities: [] },
      load: { ...depth.load, sufficient: false, ratio: null, band: null, unrated_sessions: 0, weeks: [] },
    };
    apiRequest.mockResolvedValue(empty);
    renderWith(<CoachTrainingDepthPanel userId="u-1" />);
    expect(await screen.findAllByText("No workouts in this period.")).toHaveLength(2);
    expect(screen.getByText(/The comparison appears after 3 weeks/)).toBeInTheDocument();
    expect(screen.queryByTestId("load-band")).toBeNull();
  });

  it("shows the member only the slots that hold something", async () => {
    apiRequest.mockResolvedValue({
      ...depth,
      qualities: { sessions: 0, felt_entries: 0, qualities: [] },
      load: { ...depth.load, sufficient: false, ratio: null, band: null, unrated_sessions: 0, weeks: [] },
    });
    renderWith(<ProgressDepthSections filter={{ range: "4w", sources: [] }} />);
    expect(await screen.findByRole("region", { name: "Muscle coverage" })).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Fitness qualities" })).toBeNull();
    expect(screen.queryByRole("region", { name: "Training load" })).toBeNull();
    expect(screen.queryByText("No workouts in this period.")).toBeNull();
  });

  it("gives the coach the client's shared view without atlas links, by range", async () => {
    apiRequest.mockResolvedValue(depth);
    renderWith(<CoachTrainingDepthPanel userId="u-1" />);
    await screen.findByText("1.4 : 1");
    const coverage = screen.getByRole("region", { name: "Muscle coverage" });
    expect(apiRequest).toHaveBeenCalledWith("/staff/clients/u-1/progress-depth?range=4w", { token: "token" });
    expect(within(coverage).queryByRole("link")).toBeNull();
    expect(within(coverage).getByText("Quadriceps")).toBeInTheDocument();
    expect(screen.getByText("Only from entries the client shares with the box's coaches.")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "3 months" }));
    await waitFor(() =>
      expect(apiRequest).toHaveBeenCalledWith("/staff/clients/u-1/progress-depth?range=12w", { token: "token" }),
    );
  });
});
