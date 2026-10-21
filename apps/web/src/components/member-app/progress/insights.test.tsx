import { fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import { insightSlot, insightValues } from "@/lib/progress/insights";
import type { Insight } from "@/api/insights";

import { InsightsCard } from "./InsightsCard";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

const base = { period_start: "2026-07-30", period_end: "2026-10-21", weeks: 11 };
const sleep = { ...base, rule: "sleep_prs", variant: "more_after_goal", params: { ratio: 2.4, hours: 7 } } as Insight;
const cravings = {
  ...base,
  weeks: 9,
  rule: "cravings",
  variant: "part_and_trigger",
  params: { part: "night", part_count: 6, total: 10, trigger: "stress", trigger_count: 5, with_trigger: 8 },
} as Insight;

const slot = (overrides: Record<string, unknown> = {}) => ({
  state: "insights",
  insights: [sleep, cravings],
  hidden_count: 0,
  data_weeks: 11,
  min_weeks: 4,
  window_weeks: 12,
  max_shown: 3,
  computed_at: "2026-10-21T02:40:00Z",
  ...overrides,
});

function renderCard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        <InsightsCard />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("insight helpers (ADR-166)", () => {
  it("maps each finding to its copy key and values", () => {
    expect(insightValues(sleep)).toEqual({ key: "sleep_prs.more_after_goal", values: { ratio: 2.4, hours: 7 } });
    expect(insightValues(cravings)).toEqual({
      key: "cravings.part_and_trigger",
      values: { count: 6, total: 10, part: "night", trigger: "stress" },
    });
    expect(insightValues({ ...cravings, variant: "trigger" })?.values).toEqual({ count: 5, total: 8, trigger: "stress" });
    expect(insightValues({ ...sleep, params: { hours: 7 } })).toBeNull();
    expect(insightValues({ ...cravings, params: { ...cravings.params, part: "noon" } } as unknown as Insight)).toBeNull();
  });

  it("tolerates partial answers and drops unknown findings", () => {
    expect(insightSlot({})).toMatchObject({ state: "collecting", insights: [], dataWeeks: 0, minWeeks: 4, windowWeeks: 12 });
    expect(insightSlot(undefined).state).toBe("collecting");

    const unknown = { ...sleep, rule: "horoscope" } as unknown as Insight;
    expect(insightSlot(slot({ insights: [unknown, sleep] }) as never).insights).toEqual([sleep]);
    expect(insightSlot(slot({ insights: [unknown], hidden_count: 1 }) as never).state).toBe("all_hidden");
    expect(insightSlot(slot({ insights: [sleep, cravings, sleep, cravings], max_shown: 3 }) as never).insights).toHaveLength(3);
  });
});

describe("Πρόοδος › Insights card (ADR-166)", () => {
  beforeEach(() => apiRequest.mockReset());

  it("shows findings as indicators and hides one on request", async () => {
    apiRequest.mockImplementation((path: string) =>
      Promise.resolve(path === "/me/insights" ? slot() : slot({ insights: [cravings], hidden_count: 1 })),
    );
    renderCard();

    const card = await screen.findByRole("region", { name: "Insights" });
    await within(card).findByText("You set PRs 2.4× more often after 7+ hours of sleep.");
    expect(within(card).getByText("Most of your cravings (6 of 10) come late at night, usually with stress.")).toBeInTheDocument();
    expect(within(card).getByText("From 11 weeks of data · An indicator, not medical advice.")).toBeInTheDocument();
    expect(apiRequest).toHaveBeenCalledWith("/me/insights", { token: "token", scope: "account" });

    fireEvent.click(within(card).getAllByRole("button", { name: "Hide" })[0]);
    await within(card).findByText("Hidden: 1");
    expect(apiRequest).toHaveBeenCalledWith("/me/insights/sleep_prs/dismiss", { token: "token", scope: "account", method: "POST" });
    expect(within(card).queryByText(/after 7\+ hours of sleep/)).not.toBeInTheDocument();

    apiRequest.mockResolvedValue(slot());
    fireEvent.click(within(card).getByRole("button", { name: "Show again" }));
    await within(card).findByText("You set PRs 2.4× more often after 7+ hours of sleep.");
    expect(apiRequest).toHaveBeenLastCalledWith("/me/insights/restore", { token: "token", scope: "account", method: "POST" });
  });

  it("keeps its slot with a sufficiency empty state", async () => {
    apiRequest.mockResolvedValue(slot({ state: "collecting", insights: [], data_weeks: 2 }));
    renderCard();
    const card = await screen.findByRole("region", { name: "Insights" });
    await within(card).findByText(
      "Insights appear after 4 weeks of entries (sleep, water, cravings, workouts). So far: 2 of 4.",
    );
    expect(within(card).getByText("An indicator, not medical advice.")).toBeInTheDocument();
  });

  it("says when there is no clear pattern, and reads an empty answer as collecting", async () => {
    apiRequest.mockResolvedValue(slot({ state: "no_pattern", insights: [] }));
    const { unmount } = renderCard();
    await screen.findByText("No clear pattern in the last 12 weeks. Insights update every night.");
    unmount();

    apiRequest.mockResolvedValue({});
    renderCard();
    await screen.findByText(/So far: 0 of 4\./);
  });
});
