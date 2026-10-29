import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../../messages/el.json";
import en from "../../../../../messages/en.json";
import { ApiError } from "@/api/client";
import type { FinanceRecord } from "@/api/finance";

const api = vi.hoisted(() => ({ updateFinancePackage: vi.fn() }));
vi.mock("@/api/finance", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "kypseli", adminHref: (href: string) => href }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
  usePathname: () => "/admin/finance",
}));

import { SoldOnlineBadge } from "./SoldOnlineBadge";
import { SoldOnlineCard } from "./SoldOnlineCard";

const PACKAGE: FinanceRecord = {
  id: "pkg-1",
  name: "Unlimited",
  active: true,
  base_price_cents: 7500,
  sold_online: true,
  online_visibility: "visible",
};

function wrap(node: React.ReactNode, locale: "el" | "en" = "el") {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale={locale} messages={locale === "el" ? el : en}>
        {node}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("SoldOnlineCard (ADR-271, mockup p1 A)", () => {
  beforeEach(() => {
    api.updateFinancePackage.mockReset();
  });

  it("shows the switch on and says members see the package", () => {
    wrap(<SoldOnlineCard token="token" pkg={PACKAGE} />);
    expect(screen.getByRole("switch", { name: "Πωλείται online" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByTestId("sold-online-hint")).toHaveTextContent("Στη Σελίδα πακέτων και στο app του μέλους box.");
  });

  it("saves the owner's «off» at once and says so", async () => {
    api.updateFinancePackage.mockResolvedValue({ package: { ...PACKAGE, sold_online: false, online_visibility: "off" } });
    wrap(<SoldOnlineCard token="token" pkg={PACKAGE} />);

    fireEvent.click(screen.getByRole("switch", { name: "Πωλείται online" }));

    await waitFor(() => expect(api.updateFinancePackage).toHaveBeenCalledWith("token", "pkg-1", { sold_online: false }));
    expect(await screen.findByRole("status")).toHaveTextContent("Αποθηκεύτηκε");
  });

  it("explains why a package marked sold online is not visible, with the fix", () => {
    wrap(<SoldOnlineCard token="token" pkg={{ ...PACKAGE, online_visibility: "purpose_off" }} />);
    const hint = screen.getByTestId("sold-online-hint");
    expect(hint).toHaveTextContent("Δεν φαίνεται ακόμη: αυτό το είδος πακέτου είναι κλειστό στο «Τι πληρώνεται online».");
    expect(screen.getByRole("link", { name: /Άνοιξέ το/ })).toHaveAttribute("href", "/admin/settings?tab=payments");
  });

  it("says buying opens after connecting when no provider is connected", () => {
    wrap(<SoldOnlineCard token="token" pkg={{ ...PACKAGE, online_visibility: "no_provider" }} />, "en");
    expect(screen.getByTestId("sold-online-hint")).toHaveTextContent("Buying opens once you connect online payments.");
    expect(screen.getByRole("link", { name: /Settings › Payments/ })).toBeVisible();
  });

  it("does not let a free package be sold online", () => {
    wrap(<SoldOnlineCard token="token" pkg={{ ...PACKAGE, base_price_cents: 0, sold_online: false, online_visibility: "free" }} />);
    const toggle = screen.getByRole("switch", { name: "Πωλείται online" });
    expect(toggle).toBeDisabled();
    expect(toggle).toHaveAttribute("aria-checked", "false");
    expect(screen.getByTestId("sold-online-hint")).toHaveTextContent("Τα δωρεάν πακέτα συνδρομής δεν πωλούνται online.");
  });

  it("keeps a refused save inside the card", async () => {
    const refusal = new ApiError(422, "validation_failed", { code: "validation_failed", errors: { sold_online: ["is invalid"] } } as never);
    api.updateFinancePackage.mockImplementation(async () => {
      throw refusal;
    });
    wrap(<SoldOnlineCard token="token" pkg={PACKAGE} />, "en");
    fireEvent.click(screen.getByRole("switch", { name: "Sold online" }));
    expect(await screen.findByRole("alert")).toBeVisible();
    expect(screen.getByTestId("sold-online-card")).toContainElement(screen.getByRole("alert"));
  });
});

describe("SoldOnlineBadge", () => {
  it("shows «Online», «Online · δεν φαίνεται», or nothing", () => {
    const { rerender } = wrap(<SoldOnlineBadge pkg={PACKAGE} />);
    expect(screen.getByTestId("sold-online-badge")).toHaveTextContent("Online");
    rerender(
      <QueryClientProvider client={new QueryClient()}>
        <NextIntlClientProvider locale="el" messages={el}>
          <SoldOnlineBadge pkg={{ ...PACKAGE, online_visibility: "no_provider" }} />
        </NextIntlClientProvider>
      </QueryClientProvider>,
    );
    expect(screen.getByTestId("sold-online-badge")).toHaveTextContent("Online · δεν φαίνεται");
    rerender(
      <QueryClientProvider client={new QueryClient()}>
        <NextIntlClientProvider locale="el" messages={el}>
          <SoldOnlineBadge pkg={{ ...PACKAGE, sold_online: false, online_visibility: "off" }} />
        </NextIntlClientProvider>
      </QueryClientProvider>,
    );
    expect(screen.queryByTestId("sold-online-badge")).toBeNull();
  });
});
