import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { buyPackage, fetchPackageTerms, type PublicPackage } from "@/api/my-payments";
import { openCheckout } from "@/lib/platform/checkout";

import { BuyPackageSheet } from "./BuyPackageSheet";
import { pendingCheckout } from "./checkout-flow";

const push = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push, replace: vi.fn() }) }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, status: "authenticated" }),
}));
vi.mock("@/lib/platform/checkout", () => ({ openCheckout: vi.fn().mockResolvedValue(undefined) }));
vi.mock("@/api/my-payments", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/my-payments")>()),
  fetchPackageTerms: vi.fn(),
  buyPackage: vi.fn(),
}));

const unl: PublicPackage = {
  id: "unl",
  name: "Unlimited",
  description: "Απεριόριστες επισκέψεις",
  package_type: "membership",
  billing_period: "monthly",
  base_price_cents: 7500,
  currency: "EUR",
  services: { "group_classes.included": true },
};
const v12: PublicPackage = { ...unl, id: "v12", name: "12 επισκέψεις", package_type: "visit_pack", billing_period: "one_off", base_price_cents: 9000 };
const drop: PublicPackage = { ...unl, id: "drop", name: "Μία επίσκεψη", package_type: "drop_in", billing_period: "one_off", base_price_cents: 1500 };

const terms = (over: Record<string, unknown> = {}) => ({
  package: unl,
  available: true,
  provider: "viva",
  withdrawal_days: 14,
  start_now_text: "Ζητώ να ξεκινήσει το πακέτο αμέσως. (κείμενο του API)",
  consent_text: "Επιτρέπω στην επιχείρηση «Box» να χρεώνει αυτή την κάρτα… (κείμενο του API)",
  consent_version: "2026-10-v1",
  ...over,
});

function renderSheet(mode: Parameters<typeof BuyPackageSheet>[0]["mode"], packages = [unl, v12, drop]) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="el" messages={el}>
        <BuyPackageSheet slug="box-k" packages={packages} mode={mode} origin={mode.kind === "renew" ? "box" : "schedule"} onClose={vi.fn()} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
});

describe("Πληρωμή πακέτου (mockup s4 option B)", () => {
  it("renews: picks a package, then asks when it starts and whether the card renews it, nothing chosen in advance", async () => {
    vi.mocked(fetchPackageTerms).mockResolvedValue(terms() as never);
    vi.mocked(buyPackage).mockResolvedValue({
      payment: { id: "pay-1", redirect_url: "https://checkout.viva.example/pay?ref=1" },
    } as never);
    renderSheet({ kind: "renew" });

    expect(screen.getByText("Ανανέωση", { selector: "h2, h1, [id]" })).toBeInTheDocument();
    // Single visits are for booking, not for renewing.
    expect(screen.queryByText("Μία επίσκεψη")).toBeNull();
    expect(screen.getByRole("radio", { name: /Unlimited/ })).toHaveAttribute("aria-checked", "true");
    fireEvent.click(screen.getByRole("button", { name: "Συνέχεια" }));

    expect(await screen.findByText(/Ζητώ να ξεκινήσει το πακέτο αμέσως/)).toBeInTheDocument();
    expect(screen.getByText(/Επιτρέπω στην επιχείρηση/)).toBeInTheDocument();
    const pay = screen.getByRole("button", { name: /^Πληρωμή 75,00\s€ με Viva$/ });
    expect(pay).toBeDisabled();

    fireEvent.click(screen.getByTestId("pay-start-now"));
    expect(pay).toBeDisabled();
    fireEvent.click(screen.getByTestId("pay-auto-yes"));
    expect(pay).toBeEnabled();
    fireEvent.click(pay);

    await waitFor(() =>
      expect(buyPackage).toHaveBeenCalledWith(
        "access",
        "box-k",
        "unl",
        expect.objectContaining({ start_now: true, save_card: true, consent_accepted: true, autopay: true, language: "el" }),
      ),
    );
    await waitFor(() => expect(openCheckout).toHaveBeenCalledWith("https://checkout.viva.example/pay?ref=1", expect.objectContaining({ paymentId: "pay-1" })));
    expect(pendingCheckout("pay-1")).toMatchObject({ slug: "box-k", kind: "package", origin: "box", autopay: true });
  });

  it("paying myself saves no card", async () => {
    vi.mocked(fetchPackageTerms).mockResolvedValue(terms() as never);
    vi.mocked(buyPackage).mockResolvedValue({ payment: { id: "pay-2", redirect_url: "https://checkout.viva.example/2" } } as never);
    renderSheet({ kind: "renew" });
    fireEvent.click(screen.getByRole("button", { name: "Συνέχεια" }));
    fireEvent.click(await screen.findByTestId("pay-start-now"));
    fireEvent.click(screen.getByTestId("pay-auto-no"));
    fireEvent.click(screen.getByTestId("pay-submit"));
    await waitFor(() => expect(buyPackage).toHaveBeenCalled());
    const body = vi.mocked(buyPackage).mock.calls[0][3];
    expect(body).not.toHaveProperty("save_card");
    expect(body).not.toHaveProperty("autopay");
  });

  it("booking without a package: one visit is paid and booked in one press, with no questions", async () => {
    vi.mocked(fetchPackageTerms).mockResolvedValue(terms({ withdrawal_days: null, start_now_text: null, package: drop }) as never);
    vi.mocked(buyPackage).mockResolvedValue({
      payment: { id: "pay-3", redirect_url: `${window.location.origin}/pay/return?payment=pay-3&sandbox_checkout=sbxo_1` },
    } as never);
    renderSheet({ kind: "booking", booking: { id: "slot-1", label: "CrossFit · Πεμ 18:00" } });

    expect(screen.getByText("Δεν έχεις πακέτο συνδρομής που να καλύπτει αυτό το τμήμα.")).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /Μόνο αυτή η επίσκεψη/ })).toHaveAttribute("aria-checked", "true");
    const pay = await screen.findByRole("button", { name: /^Πληρωμή 15,00\s€ και κράτηση$/ });
    expect(screen.getByText(/δεν ισχύει η υπαναχώρηση 14 ημερών/)).toBeInTheDocument();
    fireEvent.click(pay);

    await waitFor(() =>
      expect(buyPackage).toHaveBeenCalledWith("access", "box-k", "drop", expect.objectContaining({ book_slot_id: "slot-1" })),
    );
    expect(vi.mocked(fetchPackageTerms).mock.calls[0][4]).toBe("slot-1");
    // The sandbox provider comes back to our own page: no in-app browser.
    await waitFor(() => expect(push).toHaveBeenCalledWith("/pay/return?payment=pay-3&sandbox_checkout=sbxo_1"));
    expect(openCheckout).not.toHaveBeenCalled();
    expect(pendingCheckout("pay-3")).toMatchObject({ kind: "visit", origin: "schedule", classLabel: "CrossFit · Πεμ 18:00" });
  });

  it("booking without a package: a package goes through «Πριν πληρώσεις» and books the class once paid", async () => {
    vi.mocked(fetchPackageTerms).mockResolvedValue(terms({ package: unl }) as never);
    vi.mocked(buyPackage).mockResolvedValue({ payment: { id: "pay-4", redirect_url: "https://checkout.viva.example/4" } } as never);
    renderSheet({ kind: "booking", booking: { id: "slot-1", label: "CrossFit" } });

    fireEvent.click(screen.getByRole("radio", { name: /Πακέτο συνδρομής «Unlimited»/ }));
    fireEvent.click(screen.getByRole("button", { name: "Συνέχεια" }));
    fireEvent.click(await screen.findByTestId("pay-start-now"));
    fireEvent.click(screen.getByTestId("pay-auto-no"));
    fireEvent.click(screen.getByTestId("pay-submit"));
    await waitFor(() =>
      expect(buyPackage).toHaveBeenCalledWith("access", "box-k", "unl", expect.objectContaining({ book_slot_id: "slot-1", start_now: true })),
    );
  });

  it("shows the refusal inside the sheet when online payment is off", async () => {
    vi.mocked(fetchPackageTerms).mockResolvedValue(terms({ available: false }) as never);
    renderSheet({ kind: "renew" });
    fireEvent.click(screen.getByRole("button", { name: "Συνέχεια" }));
    expect(await screen.findByText(el.Pay.errorUnavailable)).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("pay-start-now"));
    fireEvent.click(screen.getByTestId("pay-auto-no"));
    expect(screen.getByTestId("pay-submit")).toBeDisabled();
  });
});
