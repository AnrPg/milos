import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { completeSandboxCheckout, fetchPayment, returnFromCheckout } from "@/api/my-payments";

import { rememberCheckout } from "./checkout-flow";
import { PaymentReturnPage } from "./PaymentReturnPage";

const nav = vi.hoisted(() => ({ search: "", replace: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: nav.replace }),
  useSearchParams: () => new URLSearchParams(nav.search),
}));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, status: "authenticated" }),
}));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "selected-box" }));
vi.mock("@/lib/platform/checkout", () => ({ finishCheckout: vi.fn().mockResolvedValue(undefined) }));
vi.mock("@/api/my-payments", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/my-payments")>()),
  returnFromCheckout: vi.fn(),
  fetchPayment: vi.fn(),
  completeSandboxCheckout: vi.fn(),
}));

const PAYMENT = "8b0e7f7a-1d2c-4c8e-9a43-0c1d2e3f4a5b";

const payment = (over: Record<string, unknown> = {}) => ({
  payment: {
    id: PAYMENT,
    provider: "viva",
    environment: "live",
    initiation: "payer",
    purpose_type: "membership_package",
    purpose_id: "pkg",
    amount_cents: 7500,
    currency: "EUR",
    description: "Unlimited",
    status: "succeeded",
    fulfilment_status: "done",
    refunded_cents: 0,
    declines: 0,
    retries: 3,
    card_last4: "4421",
    metadata: {},
    ...over,
  },
});

function renderPage(search: string) {
  nav.search = search;
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="el" messages={el}>
        <PaymentReturnPage />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
});

describe("/pay/return (mockup s4 «Επιστροφή»)", () => {
  it("asks the API about the payment at the box it was started in and shows it done", async () => {
    rememberCheckout({ paymentId: PAYMENT, slug: "box-k", kind: "package", itemName: "Unlimited", origin: "box", autopay: true });
    vi.mocked(returnFromCheckout).mockResolvedValue(payment() as never);
    renderPage(`payment=${PAYMENT}&s=1234567890&t=tx-1`);

    expect(await screen.findByText("Έτοιμο!")).toBeInTheDocument();
    expect(returnFromCheckout).toHaveBeenCalledWith("access", "box-k", { payment_id: PAYMENT, provider_ref: "1234567890", transaction_id: "tx-1" });
    expect(screen.getByText("Το πακέτο συνδρομής «Unlimited» ξεκινά σήμερα.")).toBeInTheDocument();
    expect(screen.getByText(/κάρτα ••4421/)).toBeInTheDocument();
    expect(screen.getByTestId("pay-receipt")).toHaveAttribute("href", `/me/payments?box=box-k&payment=${PAYMENT}`);
    expect(screen.getByTestId("pay-back")).toHaveTextContent("Πίσω στο Box");
  });

  it("a booked visit leads back to the schedule", async () => {
    rememberCheckout({ paymentId: PAYMENT, slug: "box-k", kind: "visit", itemName: "Μία επίσκεψη", origin: "schedule", autopay: false, classLabel: "CrossFit · Πεμ 18:00" });
    vi.mocked(returnFromCheckout).mockResolvedValue(payment() as never);
    renderPage(`payment=${PAYMENT}`);
    expect(await screen.findByText("Η θέση σου κλείστηκε")).toBeInTheDocument();
    expect(screen.getByText(/CrossFit · Πεμ 18:00/)).toBeInTheDocument();
    expect(screen.getByTestId("pay-back")).toHaveAttribute("href", "/box/schedule");
  });

  it("waits for the bank and checks again", async () => {
    vi.mocked(returnFromCheckout).mockResolvedValueOnce(payment({ status: "processing" }) as never);
    vi.mocked(returnFromCheckout).mockResolvedValueOnce(payment() as never);
    renderPage(`payment=${PAYMENT}`);
    expect(await screen.findByText("Περιμένουμε την τράπεζα")).toBeInTheDocument();
    // Without a remembered checkout, the selected box is asked.
    expect(vi.mocked(returnFromCheckout).mock.calls[0][1]).toBe("selected-box");
    fireEvent.click(screen.getByTestId("pay-check-again"));
    expect(await screen.findByText("Έτοιμο!")).toBeInTheDocument();
  });

  it("says plainly when the bank declined it or the payer cancelled", async () => {
    vi.mocked(returnFromCheckout).mockResolvedValue(payment({ status: "failed" }) as never);
    const { unmount } = renderPage(`payment=${PAYMENT}`);
    expect(await screen.findByText("Η πληρωμή δεν έγινε")).toBeInTheDocument();
    expect(screen.getByText(/Δεν χρεώθηκες/)).toBeInTheDocument();
    unmount();

    vi.mocked(returnFromCheckout).mockResolvedValue(payment({ status: "awaiting_payer" }) as never);
    renderPage(`payment=${PAYMENT}&cancelled=1`);
    expect(await screen.findByText("Η πληρωμή ακυρώθηκε")).toBeInTheDocument();
  });

  it("a link without a payment explains itself", () => {
    renderPage("");
    expect(screen.getByText("Δεν βρήκαμε αυτή την πληρωμή")).toBeInTheDocument();
    expect(returnFromCheckout).not.toHaveBeenCalled();
  });

  it("plays the sandbox provider's page only with sandbox_checkout, then shows the result", async () => {
    rememberCheckout({ paymentId: PAYMENT, slug: "box-k", kind: "package", itemName: "Unlimited", origin: "box", autopay: false });
    vi.mocked(fetchPayment).mockResolvedValue(payment({ status: "awaiting_payer" }) as never);
    vi.mocked(completeSandboxCheckout).mockResolvedValue(payment() as never);
    renderPage(`payment=${PAYMENT}&sandbox_checkout=sbxo_abc&sandbox_decline=0`);

    expect(screen.getByTestId("pay-sandbox")).toBeInTheDocument();
    const pay = await screen.findByTestId("pay-sandbox-pay");
    await waitFor(() => expect(pay).toBeEnabled());
    fireEvent.click(pay);
    await waitFor(() => expect(completeSandboxCheckout).toHaveBeenCalledWith("access", "box-k", "sbxo_abc", "succeeded", false));
    expect(nav.replace).toHaveBeenCalledWith(`/pay/return?payment=${PAYMENT}`);
    expect(returnFromCheckout).not.toHaveBeenCalled();
  });

  it("the sandbox cancel button comes back cancelled", async () => {
    vi.mocked(fetchPayment).mockResolvedValue(payment({ status: "awaiting_payer" }) as never);
    vi.mocked(completeSandboxCheckout).mockResolvedValue(payment({ status: "cancelled" }) as never);
    renderPage(`payment=${PAYMENT}&sandbox_checkout=sbxo_abc&sandbox_decline=1`);
    fireEvent.click(screen.getByTestId("pay-sandbox-cancel"));
    await waitFor(() => expect(completeSandboxCheckout).toHaveBeenCalledWith("access", "selected-box", "sbxo_abc", "cancelled", true));
    expect(nav.replace).toHaveBeenCalledWith(`/pay/return?payment=${PAYMENT}&cancelled=1`);
  });
});
