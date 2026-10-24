import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { NutritionPlanCard } from "./CoachingConsole";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

const plan = {
  id: "plan-1",
  title: "Lean bulk",
  body: "Eat well.",
  protein_grams: 160,
  carbs_grams: 250,
  fat_grams: 70,
  updated_at: "2026-10-20T10:00:00Z",
};
const preferences = (hide: boolean) => ({
  water_goal_ml: 2000,
  glass_ml: 250,
  sleep_goal_minutes: 420,
  hidden_items: [],
  item_order: ["water", "sleep", "meals", "plan", "mood"],
  water_reminder: true,
  hide_macros: hide,
});

function renderCard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        <NutritionPlanCard />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("the coach's nutrition plan (vision §8.6, ADR-194)", () => {
  beforeEach(() => apiRequest.mockReset());

  it("shows the macros and hides them on the member's wish, kept server-side", async () => {
    let hidden = false;
    apiRequest.mockImplementation(async (path: string, options?: { method?: string; body?: { hide_macros: boolean } }) => {
      if (path === "/me/nutrition-plan") return { nutrition_plan: plan };
      if (path === "/me/wellness/preferences" && options?.method === "PUT") {
        hidden = options.body!.hide_macros;
        return { preferences: preferences(hidden) };
      }
      if (path === "/me/wellness/preferences") return { preferences: preferences(hidden) };
      return {};
    });

    renderCard();
    expect(await screen.findByText("160 g")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Hide numbers" }));
    await waitFor(() => expect(screen.queryByText("160 g")).toBeNull());
    expect(hidden).toBe(true);
    expect(screen.getByText("Numbers hidden")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Show numbers" }).getAttribute("aria-pressed")).toBe("true");
  });

  it("keeps hidden macros hidden", async () => {
    apiRequest.mockImplementation(async (path: string) =>
      path === "/me/nutrition-plan" ? { nutrition_plan: plan } : { preferences: preferences(true) },
    );
    renderCard();
    expect(await screen.findByRole("button", { name: "Show numbers" })).toBeTruthy();
    expect(screen.queryByText("160 g")).toBeNull();
  });

  it("shows no card without a plan", async () => {
    apiRequest.mockImplementation(async () => ({ nutrition_plan: null }));
    const { container } = renderCard();
    await waitFor(() => expect(apiRequest).toHaveBeenCalledWith("/me/nutrition-plan", expect.anything()));
    await waitFor(() => expect(container.textContent).toBe(""));
    expect(apiRequest).toHaveBeenCalledTimes(1);
  });
});
