import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ExecutionKpiDashboard } from "./ExecutionKpiDashboard";

const fetchAdminAnalyticsSummary = vi.fn();

vi.mock("@/api/analytics", () => ({
  fetchAdminAnalyticsSummary: (...args: unknown[]) => fetchAdminAnalyticsSummary(...args),
}));
vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, params?: Record<string, unknown>) =>
    params ? `${key}:${JSON.stringify(params)}` : key,
}));
vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "en" }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/components/semantic-label", () => ({ SemanticLabel: ({ value }: { value: string }) => <>{value}</> }));
vi.mock("@/components/HelpTooltip", () => ({ HelpTooltip: () => null }));

const report = {
  started: 4,
  completed: 3,
  completion_rate: 0.75,
  score_capture_rate: 0.5,
  skip_rate_on_countdowns: 0.1,
  skips: 2,
  pauses_per_execution: 1.5,
  average_paused_ms: 30_000,
  median_time_to_first_start_ms: 42_000,
  median_completed_duration_ms: 720_000,
  clock_adjustment_rate: 0.25,
  finish_wizard_drop_off_rate: 0.2,
  abandon_points: [{ format: "emom", section_name: "EMOM 10", segment_index: 4, count: 1 }],
  abandon_by_format: [{ format: "emom", count: 1, share: 1 }],
  by_format: [{ key: "emom", started: 2, completed: 1, completion_rate: 0.5 }],
  by_source: [{ key: "self_selected", started: 4, completed: 3, completion_rate: 0.75 }],
  structured: { started: 3, completed: 3 },
  free_text: { started: 1, completed: 0, completion_rate: 0, median_abandon_elapsed_ms: 120_000 },
  daily: [
    { date: "2026-10-10", started: 1, completed: 1 },
    { date: "2026-10-11", started: 3, completed: 2 },
  ],
};

function renderDashboard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ExecutionKpiDashboard />
    </QueryClientProvider>,
  );
}

describe("ExecutionKpiDashboard", () => {
  beforeEach(() => {
    fetchAdminAnalyticsSummary.mockReset();
    fetchAdminAnalyticsSummary.mockResolvedValue({ execution: report });
  });

  it("shows headline KPIs, stopping points and a table view of the trend", async () => {
    renderDashboard();

    expect(await screen.findByText('kpiCompletedOfStarted:{"completed":3,"started":4}')).toBeInTheDocument();
    expect(screen.getAllByText("75%").length).toBeGreaterThan(0);
    expect(screen.getByText("0:42")).toBeInTheDocument();
    expect(screen.getByText("EMOM 10")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: /kpiDailyTrendSummary/ })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "kpiShowTable" }));
    expect(screen.getByRole("columnheader", { name: "kpiColumnDate" })).toBeInTheDocument();
    expect(screen.queryByRole("img", { name: /kpiDailyTrendSummary/ })).not.toBeInTheDocument();
  });

  it("refetches for another period", async () => {
    renderDashboard();
    await screen.findByText("0:42");

    fireEvent.click(screen.getByRole("button", { name: 'kpiLastDays:{"days":7}' }));
    expect(fetchAdminAnalyticsSummary).toHaveBeenLastCalledWith("token", 7);
  });
});
