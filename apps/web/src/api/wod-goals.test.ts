import { beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();

vi.mock("@/api/client", () => ({
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));

import {
  fetchAdminWorkoutGoals,
  fetchAnatomyTaxonomy,
  fetchGoalFeedback,
  fetchWorkoutGoals,
  saveAdminWorkoutGoals,
  saveGoalFeedback,
} from "@/api/wod-goals";

describe("WOD goals requests", () => {
  beforeEach(() => {
    apiRequest.mockReset();
    apiRequest.mockResolvedValue({});
  });

  it("reads the taxonomy and the member's goals", async () => {
    await fetchAnatomyTaxonomy("t");
    expect(apiRequest).toHaveBeenLastCalledWith("/anatomy/taxonomy", { token: "t" });
    await fetchWorkoutGoals("t", "w 1");
    expect(apiRequest).toHaveBeenLastCalledWith("/workouts/w%201/goals", { token: "t" });
  });

  it("reads and saves the coach's goals", async () => {
    await fetchAdminWorkoutGoals("t", "w-1");
    expect(apiRequest).toHaveBeenLastCalledWith("/admin/workouts/w-1/goals", { token: "t" });
    const body = { muscles: [{ id: "quadriceps", role: "primary" as const }], qualities: ["stamina"], stimulus: null, visible_to_members: true };
    await saveAdminWorkoutGoals("t", "w-1", body);
    expect(apiRequest).toHaveBeenLastCalledWith("/admin/workouts/w-1/goals", { method: "PUT", token: "t", body });
  });

  it("reads and saves feedback on an entry", async () => {
    await fetchGoalFeedback("t", "execution", "e-1");
    expect(apiRequest).toHaveBeenLastCalledWith("/me/goal-feedback/execution/e-1", { token: "t" });
    const body = { felt_muscles: ["glutes"], felt_qualities: [] };
    await saveGoalFeedback("t", "training_log", "l-1", body);
    expect(apiRequest).toHaveBeenLastCalledWith("/me/goal-feedback/training_log/l-1", { method: "PUT", token: "t", body });
  });
});
