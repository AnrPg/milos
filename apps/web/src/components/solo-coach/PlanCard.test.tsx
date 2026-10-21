import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { PlanCard, PlanNotice } from "./PlanCard";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "en" }));

const fetchAdminPlan = vi.fn();
vi.mock("@/api/platform-plans", () => ({
  ADMIN_PLAN_KEY: ["admin", "plan"],
  fetchAdminPlan: (token: string) => fetchAdminPlan(token),
}));

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const plan = {
  code: "gym_small",
  name: "Gym S",
  currency: "EUR",
  monthly_price_cents: null,
  price_confirmed: false,
};

describe("PlanNotice and PlanCard", () => {
  beforeEach(() => fetchAdminPlan.mockReset());

  // A partial answer must never break the Settings page they sit on.
  it("show nothing for an answer without a plan or usage", async () => {
    fetchAdminPlan.mockResolvedValue({});
    const { container } = render(wrap(<><PlanNotice token="t" /><PlanCard token="t" /></>));
    await vi.waitFor(() => expect(fetchAdminPlan).toHaveBeenCalled());
    await vi.waitFor(() => expect(container.textContent).toBe(""));
  });

  it("render a plan whose usage is missing without crashing", async () => {
    fetchAdminPlan.mockResolvedValue({ plan, status: "active", notice: null });
    render(wrap(<><PlanNotice token="t" /><PlanCard token="t" /></>));
    expect(await screen.findByText("Gym S")).toBeTruthy();
    expect(screen.queryByRole("status")).toBeNull();
  });

  it("warn when the staff seats are full", async () => {
    fetchAdminPlan.mockResolvedValue({
      plan,
      status: "active",
      notice: null,
      usage: [{ key: "staff_seats", used: 3, limit: 3, hard: true, state: "reached" }],
    });
    render(wrap(<PlanNotice token="t" />));
    expect(await screen.findByRole("status")).toHaveTextContent("plan.notice.staff_full");
  });
});
