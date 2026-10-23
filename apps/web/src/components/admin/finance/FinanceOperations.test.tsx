import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import type { FacilityLocation } from "@/api/facility";

// ADR-186 §7: every tab of the finance operations page follows the page branch filter.

const state = vi.hoisted(() => ({ tab: "members", param: undefined as string | undefined }));
const received = vi.hoisted(() => [] as Array<{ tab: string; props: Record<string, unknown> }>);
const api = vi.hoisted(() => ({
  fetchFinanceSummary: vi.fn(async () => ({ totals: {} })),
  fetchFinanceQueues: vi.fn(async () => ({ queues: {} })),
  fetchPackageCatalog: vi.fn(async () => ({ modules: [] })),
  fetchFinancePackages: vi.fn(async () => ({ packages: [] as Record<string, unknown>[] })),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  useSearchParams: () => new URLSearchParams({ tab: state.tab }),
  usePathname: () => "/admin/finance",
}));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationSlug: () => null,
  adminHref: (href: string) => href,
}));
vi.mock("@/api/finance", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/admin/finance/packages/package-catalog", async (original) => ({
  ...(await original<object>()),
  moduleEnabled: () => true,
}));
vi.mock("@/components/admin/BranchFilter", async (original) => ({
  ...(await original<object>()),
  useBranchFilter: () => ({
    locations: [],
    selected: state.param ? state.param.split(",") : [],
    setSelected: vi.fn(),
    param: state.param,
    visible: true,
  }),
  BranchFilterControl: () => null,
}));

function stub(tab: string) {
  function StubTab(props: Record<string, unknown>) {
    received.push({ tab, props });
    return <div data-testid={`tab-${tab}`} />;
  }
  return StubTab;
}

vi.mock("@/components/admin/finance/tabs/MembersTab", () => ({ MembersTab: stub("members") }));
vi.mock("@/components/admin/finance/tabs/SeasonsTab", () => ({ SeasonsTab: stub("seasons") }));
vi.mock("@/components/admin/finance/tabs/PromotionsTab", () => ({ PromotionsTab: stub("promotions") }));
vi.mock("@/components/admin/finance/tabs/ReferralsTab", () => ({ ReferralsTab: stub("referrals") }));
vi.mock("@/components/admin/finance/tabs/QueuesTab", () => ({ QueuesTab: stub("queues") }));
vi.mock("@/components/admin/finance/tabs/AccountingTab", () => ({ AccountingTab: stub("accounting") }));
vi.mock("@/components/admin/finance/tabs/CorporateTab", () => ({ CorporateTab: stub("corporate") }));
vi.mock("@/components/admin/finance/packages/use-package-authoring", () => ({
  usePackageAuthoring: () => ({
    catalog: null,
    classTypes: [],
    locations: [location("k", "Κηφισιά"), location("m", "Μαρούσι"), location("g", "Γλυφάδα")],
    error: null,
  }),
}));

import { FinanceOperations } from "./FinanceOperations";
import { BranchCoverageBadge } from "@/components/admin/BranchFilter";

function location(id: string, name: string): FacilityLocation {
  return { id, name, address: null, archived_at: null };
}

function wrap(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const FILTERED = ["members", "packages", "promotions", "referrals", "queues", "accounting"];
const NOTES: Record<string, string> = {
  members: en.BranchScope.filterNoteMembers,
  packages: en.BranchScope.filterNoteCovering,
  promotions: en.BranchScope.filterNoteCovering,
  referrals: en.BranchScope.filterNoteReferrals,
  queues: en.BranchScope.filterNoteMembers,
  accounting: en.BranchScope.filterNoteAccounting,
  seasons: en.BranchScope.filterNoteBusinessWide,
  corporate: en.BranchScope.filterNoteBusinessWide,
};

describe("FinanceOperations and the page branch filter", () => {
  beforeEach(() => {
    received.length = 0;
    state.param = undefined;
    Object.values(api).forEach((mock) => mock.mockClear());
  });

  it.each(FILTERED.filter((tab) => tab !== "packages"))("hands the filter to the %s tab", async (tab) => {
    state.tab = tab;
    state.param = "k,m";
    wrap(<FinanceOperations />);

    await screen.findByTestId(`tab-${tab}`);
    expect(received.at(-1)?.props.locationIds).toBe("k,m");
    expect(screen.getByRole("note")).toHaveTextContent(NOTES[tab]);
  });

  it.each(["seasons", "corporate"])("says the %s tab is business-wide", async (tab) => {
    state.tab = tab;
    state.param = "k";
    wrap(<FinanceOperations />);

    await screen.findByTestId(`tab-${tab}`);
    expect(screen.getByRole("note")).toHaveTextContent(en.BranchScope.filterNoteBusinessWide);
  });

  it("shows no note and no filter under «All»", async () => {
    state.tab = "members";
    wrap(<FinanceOperations />);

    await screen.findByTestId("tab-members");
    expect(received.at(-1)?.props.locationIds).toBeUndefined();
    expect(screen.queryByRole("note")).toBeNull();
  });

  it("lists the packages of the filter, each with where it is valid", async () => {
    api.fetchFinancePackages.mockResolvedValue({
      packages: [
        { id: "p1", name: "Κηφισιά only", active: true, fields: { "facility.location_ids": ["k"] } },
        { id: "p2", name: "Everywhere", active: true, fields: {} },
      ],
    });
    state.tab = "packages";
    state.param = "k";
    wrap(<FinanceOperations />);

    expect(await screen.findByText("Κηφισιά only")).toBeInTheDocument();
    expect(api.fetchFinancePackages).toHaveBeenCalledWith("token", "k");
    expect(screen.getByText("Κηφισιά")).toBeInTheDocument();
    expect(screen.getByText(en.BranchScope.allBranches)).toBeInTheDocument();
  });
});

describe("BranchCoverageBadge", () => {
  const locations = [location("k", "Κηφισιά"), location("m", "Μαρούσι"), location("g", "Γλυφάδα")];

  it("names the branches, shortening a long list", () => {
    const { rerender } = wrap(<BranchCoverageBadge target={["k", "m"]} locations={locations} />);
    expect(screen.getByText("Κηφισιά, Μαρούσι")).toBeInTheDocument();
    rerender(
      <NextIntlClientProvider locale="en" messages={en}>
        <BranchCoverageBadge target={["g", "k", "m"]} locations={locations} />
      </NextIntlClientProvider>,
    );
    expect(screen.getByText("Κηφισιά +2")).toBeInTheDocument();
  });

  it("is hidden for someone who sees one branch", () => {
    const { container } = wrap(<BranchCoverageBadge target="all" locations={[locations[0]]} />);
    expect(container).toBeEmptyDOMElement();
  });
});
