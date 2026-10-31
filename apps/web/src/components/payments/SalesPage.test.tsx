import { fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { fetchPackageTerms, fetchPublicPackages, type PublicPackage } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";

import { SalesPage } from "./SalesPage";

const state = vi.hoisted(() => ({
  search: "",
  status: "guest" as "guest" | "authenticated",
  memberships: [] as Array<{ organization: { slug: string } }>,
  platform: null as null | "ios" | "android",
  replace: vi.fn(),
}));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: state.replace }),
  useSearchParams: () => new URLSearchParams(state.search),
}));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: state.status === "guest" ? null : { access_token: "access" }, status: state.status }),
}));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationMemberships: () => ({ data: state.memberships, isPending: false }),
}));
vi.mock("@/lib/platform", () => ({ nativePlatform: () => state.platform }));
vi.mock("@/api/my-payments", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/my-payments")>()),
  fetchPublicPackages: vi.fn(),
  fetchPackageTerms: vi.fn(),
}));

const pkg = (id: string, over: Partial<PublicPackage> = {}): PublicPackage => ({
  id,
  name: id,
  description: null,
  package_type: "membership",
  billing_period: "monthly",
  base_price_cents: 6000,
  currency: "EUR",
  services: { "group_classes.included": true },
  ...over,
});

const PACKAGES = [
  pkg("Δοκιμαστικό", { package_type: "trial", billing_period: "one_off", base_price_cents: 1000 }),
  pkg("Unlimited", { base_price_cents: 7500 }),
  pkg("3 φορές την εβδομάδα"),
  pkg("12 επισκέψεις", { package_type: "visit_pack", billing_period: "one_off", base_price_cents: 9000 }),
  pkg("Πρωινά", { base_price_cents: 5000 }),
  pkg("Online προγραμματισμός", { package_type: "online_coaching", services: { "group_classes.included": false } }),
];

const page = { box: { name: "Box Κυψέλη", slug: "box-kypseli", organization_id: "org" } } as unknown as PublicBoxPage;

function renderPage() {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="el" messages={el}>
        <SalesPage page={page} line="CrossFit · Κυψέλη" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  state.search = "";
  state.status = "guest";
  state.memberships = [];
  state.platform = null;
  vi.mocked(fetchPublicPackages).mockResolvedValue({ packages: PACKAGES, online_payments: true, provider: "viva", withdrawal_days: 14 } as never);
});

describe("Σελίδα αγοράς πακέτων (mockup s5 option C)", () => {
  it("shows the trial first, three packages with prices, and the rest behind «Όλα»", async () => {
    renderPage();
    const trial = await screen.findByTestId("sales-trial");
    expect(within(trial).getByText(/Δοκιμαστικό τμήμα με 10,00/)).toBeInTheDocument();
    expect(screen.getByText("Unlimited")).toBeInTheDocument();
    expect(screen.getByText("3 φορές την εβδομάδα")).toBeInTheDocument();
    expect(screen.getByText("12 επισκέψεις")).toBeInTheDocument();
    expect(screen.queryByText("Πρωινά")).toBeNull();
    fireEvent.click(screen.getByTestId("sales-all"));
    expect(screen.getByText("Πρωινά")).toBeInTheDocument();
    expect(screen.getByText(/Πληρωμές μέσω Viva/)).toBeInTheDocument();
  });

  it("does not offer digital-only packages inside the store apps (ADR-256)", async () => {
    state.platform = "ios";
    renderPage();
    await screen.findByText("Unlimited");
    fireEvent.click(screen.getByTestId("sales-all"));
    expect(screen.queryByText("Online προγραμματισμός")).toBeNull();
  });

  it("a visitor signs in or signs up first and comes back to the same package", async () => {
    state.search = "buy=Unlimited";
    renderPage();
    const dialog = await screen.findByTestId("sales-buy");
    expect(within(dialog).getByTestId("sales-register")).toHaveAttribute("href", `/register?next=${encodeURIComponent("/b/box-kypseli/packages?buy=Unlimited")}`);
    expect(within(dialog).getByTestId("sales-login")).toHaveAttribute("href", `/login?next=${encodeURIComponent("/b/box-kypseli/packages?buy=Unlimited")}`);
    expect(fetchPackageTerms).not.toHaveBeenCalled();
  });

  it("someone not yet in the box joins it first", async () => {
    state.status = "authenticated";
    state.search = "buy=Unlimited";
    renderPage();
    expect(await screen.findByTestId("sales-join")).toHaveAttribute("href", "/join/box-kypseli");
  });

  it("a member of the box gets the app's «Πριν πληρώσεις»", async () => {
    state.status = "authenticated";
    state.memberships = [{ organization: { slug: "box-kypseli" } }];
    state.search = "buy=Unlimited";
    vi.mocked(fetchPackageTerms).mockResolvedValue({
      package: PACKAGES[1],
      available: true,
      provider: "viva",
      withdrawal_days: 14,
      start_now_text: "Ζητώ να ξεκινήσει (API)",
      consent_text: "Επιτρέπω (API)",
      consent_version: "v1",
    } as never);
    renderPage();
    expect(await screen.findByText("Ζητώ να ξεκινήσει (API)")).toBeInTheDocument();
    expect(screen.getByTestId("pay-submit")).toBeDisabled();
  });

  it("without online payments offers «Το θέλω» and no buy buttons (ADR-291)", async () => {
    vi.mocked(fetchPublicPackages).mockResolvedValue({ packages: PACKAGES, online_payments: false, provider: null, withdrawal_days: 14 } as never);
    renderPage();
    expect(await screen.findByTestId("sales-desk-note")).toHaveTextContent(el.DeskPay.pageNote);
    expect(screen.getAllByRole("button", { name: el.DeskPay.want }).length).toBeGreaterThan(0);
    expect(screen.queryByRole("button", { name: "Αγορά" })).toBeNull();
  });
});
