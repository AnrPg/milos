import { beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();

vi.mock("@/api/client", () => ({
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));

import { acknowledgeMyInjuryWarnings, fetchMyWorkoutInjuryWarnings } from "@/api/injury-warnings";

describe("self injury warning requests", () => {
  beforeEach(() => {
    apiRequest.mockReset();
    apiRequest.mockResolvedValue({});
  });

  it("sends the surface, execution and scale of the ready screen as query parameters", async () => {
    await fetchMyWorkoutInjuryWarnings("token", "w-1", {
      surface: "pre_start",
      source_context_id: "e-1",
      scale: "scaled",
    });

    expect(apiRequest).toHaveBeenCalledWith(
      "/me/workouts/w-1/injury-warnings?surface=pre_start&source_context_id=e-1&scale=scaled",
      { token: "token" },
    );
  });

  it("omits empty options and posts the acknowledgement body as given", async () => {
    await fetchMyWorkoutInjuryWarnings("token", "w-1", { scale: null });
    expect(apiRequest).toHaveBeenCalledWith("/me/workouts/w-1/injury-warnings", { token: "token" });

    await acknowledgeMyInjuryWarnings("token", "w-1", { surface: "pre_start", scale: "scaled" });
    expect(apiRequest).toHaveBeenLastCalledWith("/me/workouts/w-1/injury-warnings/acknowledge", {
      method: "POST",
      token: "token",
      body: { surface: "pre_start", scale: "scaled" },
    });
  });
});
