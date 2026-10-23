import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { BUSINESS_NOT_ACTIVATED_EVENT } from "@/api/client";

import { DemoModeHost } from "./DemoModeHost";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

let pathname = "/admin/users";
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "t" } }),
}));

let membership: unknown = null;
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ membership }),
}));

const fetchBusinessStatus = vi.fn();
const seedDemoData = vi.fn();
vi.mock("@/api/business-accounts", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/business-accounts")>();
  return {
    ...actual,
    fetchBusinessStatus: (token: string) => fetchBusinessStatus(token),
    seedDemoData: (token: string, section: string) => seedDemoData(token, section),
  };
});

function wrap(children: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const demoStatus = {
  activation: "demo",
  gated: true,
  activation_request: { status: "pending" },
  sections: [
    { section: "members", seeded: false, rows: 0 },
    { section: "schedule", seeded: false, rows: 0 },
    { section: "finance", seeded: false, rows: 0 },
    { section: "workouts", seeded: false, rows: 0 },
  ],
};

function demoMembership(roles: string[], activation = "demo") {
  return { roles, organization: { slug: "box-a", activation, provider_kind: "gym" } };
}

describe("DemoModeHost (ADR-184)", () => {
  beforeEach(() => {
    pathname = "/admin/users";
    fetchBusinessStatus.mockReset().mockResolvedValue(demoStatus);
    seedDemoData.mockReset().mockResolvedValue(demoStatus);
  });

  it("shows one floating button on an admin screen of a demo business and fills that screen", async () => {
    membership = demoMembership(["owner"]);
    render(wrap(<DemoModeHost />));

    fireEvent.click(await screen.findByTestId("demo-mode-button"));
    fireEvent.click(screen.getByText("demo.fill.members"));

    await vi.waitFor(() => expect(seedDemoData).toHaveBeenCalledWith("t", "members"));
    expect(screen.getAllByTestId("demo-mode-button")).toHaveLength(1);
    expect(screen.getByText("activation.pending")).toBeTruthy();
  });

  it("stays away from active businesses, members and screens outside admin", async () => {
    membership = demoMembership(["owner"], "active");
    const { unmount } = render(wrap(<DemoModeHost />));
    expect(screen.queryByTestId("demo-mode-button")).toBeNull();
    unmount();

    // Payloads without the field (older APIs, e2e stubs) are active businesses.
    membership = { roles: ["owner"], organization: { slug: "box-a", provider_kind: "gym" } };
    const noField = render(wrap(<DemoModeHost />));
    expect(screen.queryByTestId("demo-mode-button")).toBeNull();
    noField.unmount();

    membership = demoMembership(["member"]);
    const second = render(wrap(<DemoModeHost />));
    expect(screen.queryByTestId("demo-mode-button")).toBeNull();
    second.unmount();

    membership = demoMembership(["owner"]);
    pathname = "/box";
    render(wrap(<DemoModeHost />));
    await vi.waitFor(() => expect(fetchBusinessStatus).toHaveBeenCalled());
    expect(screen.queryByTestId("demo-mode-button")).toBeNull();
    expect(fetchBusinessStatus).toHaveBeenCalledTimes(1);
  });

  it("opens the friendly notice when a going-live action is refused", async () => {
    membership = demoMembership(["coach"]);
    render(wrap(<DemoModeHost />));

    act(() => {
      window.dispatchEvent(new CustomEvent(BUSINESS_NOT_ACTIVATED_EVENT));
    });

    expect(await screen.findByText("notice.title")).toBeTruthy();
    expect(screen.getByText("notice.howStaff")).toBeTruthy();
  });
});
