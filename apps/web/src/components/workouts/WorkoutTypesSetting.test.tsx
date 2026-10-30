import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";
import { WORKOUT_TYPES } from "@/lib/workout-types";

const api = vi.hoisted(() => ({
  fetchAdminSettings: vi.fn(),
  updateAdminSettings: vi.fn(),
  fetchWorkoutAuthoringSettings: vi.fn(),
}));

vi.mock("@/api/settings", () => ({ fetchAdminSettings: api.fetchAdminSettings, updateAdminSettings: api.updateAdminSettings }));
vi.mock("@/api/workouts", () => ({
  WOD_ASSISTANT_AVAILABILITY_KEY: ["authoring-settings"],
  fetchWorkoutAuthoringSettings: api.fetchWorkoutAuthoringSettings,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

import { WorkoutTypeSelect } from "./WorkoutTypeSelect";
import { WorkoutTypesSetting } from "./WorkoutTypesSetting";

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        {children}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const settings = (workout_types: string[] | null) => ({ workouts: { wod_assistant_enabled: true, wod_goals_visible_by_default: false, workout_types } });

beforeEach(() => {
  vi.clearAllMocks();
});

// ADR-275: the gym chooses which workout kinds its editors offer.
describe("WorkoutTypesSetting", () => {
  it("starts with every kind on, grouped by family in Greek", async () => {
    api.fetchAdminSettings.mockResolvedValue(settings(null));
    wrap(<WorkoutTypesSetting token="token" />);
    expect(await screen.findByRole("group", { name: "Μαχητικά αθλήματα" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Χορός" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Muay Thai" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getAllByRole("button", { pressed: true })).toHaveLength(WORKOUT_TYPES.length);
  });

  it("hides a kind by storing the others", async () => {
    api.fetchAdminSettings.mockResolvedValue(settings(null));
    api.updateAdminSettings.mockResolvedValue(settings(WORKOUT_TYPES.filter((type) => type !== "yoga")));
    wrap(<WorkoutTypesSetting token="token" />);
    fireEvent.click(await screen.findByRole("button", { name: "Γιόγκα" }));
    await waitFor(() => expect(api.updateAdminSettings).toHaveBeenCalled());
    const sent = api.updateAdminSettings.mock.calls[0][1].workouts.workout_types as string[];
    expect(sent).not.toContain("yoga");
    expect(sent).toHaveLength(WORKOUT_TYPES.length - 1);
  });

  it("stores no choice once every kind is on again", async () => {
    api.fetchAdminSettings.mockResolvedValue(settings(WORKOUT_TYPES.filter((type) => type !== "yoga")));
    api.updateAdminSettings.mockResolvedValue(settings(null));
    wrap(<WorkoutTypesSetting token="token" />);
    fireEvent.click(await screen.findByRole("button", { name: "Γιόγκα" }));
    await waitFor(() => expect(api.updateAdminSettings).toHaveBeenCalledWith("token", { workouts: { workout_types: null } }));
  });

  it("keeps the last kind on", async () => {
    api.fetchAdminSettings.mockResolvedValue(settings(["crossfit"]));
    wrap(<WorkoutTypesSetting token="token" />);
    expect(await screen.findByRole("button", { name: "CrossFit" })).toBeDisabled();
  });
});

describe("WorkoutTypeSelect", () => {
  it("offers the gym's kinds in Greek, plus the workout's own hidden kind", async () => {
    api.fetchWorkoutAuthoringSettings.mockResolvedValue({ wod_assistant_enabled: true, workout_types: ["crossfit", "boxing"] });
    wrap(<WorkoutTypeSelect value="yoga" onChange={() => {}} placeholder="Διάλεξε τύπο…" />);
    const trigger = screen.getByRole("combobox");
    await waitFor(() => expect(api.fetchWorkoutAuthoringSettings).toHaveBeenCalled());
    fireEvent.click(trigger);
    await waitFor(() => expect(screen.getAllByRole("option").map((option) => option.textContent)).toEqual(["Διάλεξε τύπο…", "CrossFit", "Γιόγκα", "Πυγμαχία"]));
    expect(screen.queryByText("crossfit")).not.toBeInTheDocument();
  });
});
