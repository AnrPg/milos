import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { ApiError } from "@/api/client";
import type { BillingProvider } from "@/api/my-billing";
import {
  fetchInvoiceTerms,
  fetchPayment,
  fetchSavedCards,
  payInvoice,
  removeSavedCard,
  setCardAutopay,
  withdrawPurchase,
} from "@/api/my-payments";
import { openCheckout } from "@/lib/platform/checkout";

import { PaymentFocusCard, SavedCardsCard } from "./MemberPayments";
import { nextOpenInvoice, PayOpenInvoice } from "./PayOpenInvoice";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }) }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, status: "authenticated" }),
}));
vi.mock("@/lib/platform/checkout", () => ({ openCheckout: vi.fn().mockResolvedValue(undefined) }));
vi.mock("@/api/my-payments", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/my-payments")>()),
  fetchPayment: vi.fn(),
  fetchInvoiceTerms: vi.fn(),
  payInvoice: vi.fn(),
  withdrawPurchase: vi.fn(),
  fetchSavedCards: vi.fn(),
  setCardAutopay: vi.fn(),
  removeSavedCard: vi.fn(),
}));

const provider = (slug: string, over: Partial<BillingProvider> = {}) =>
  ({ slug, organization_id: slug, name: slug, kind: "gym", invoices: [], ...over }) as unknown as BillingProvider;

const intent = (over: Record<string, unknown> = {}) => ({
  id: "pay-1",
  provider: "viva",
  environment: "live",
  initiation: "merchant",
  purpose_type: "finance_invoice",
  purpose_id: "inv-1",
  amount_cents: 7500,
  currency: "EUR",
  description: "INV-0042 · Unlimited",
  status: "scheduled",
  fulfilment_status: "pending",
  refunded_cents: 0,
  declines: 1,
  retries: 3,
  card_last4: "4421",
  next_attempt_at: "2026-11-01T09:00:00Z",
  metadata: {},
  ...over,
});

const invoiceTerms = { available: true, provider: "viva", amount_cents: 7500, currency: "EUR", consent_text: "Επιτρέπω (κείμενο του API)", consent_version: "v1" };

function wrap(ui: React.ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="el" messages={el}>{ui}</NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
});

describe("Εγώ › Πληρωμές ?payment= (ADR-260 failed charges, ADR-248 withdrawal)", () => {
  it("finds the payment at the right box and pays it with another card", async () => {
    vi.mocked(fetchPayment).mockImplementation(async (_token, slug) => {
      if (slug === "box-k") return { payment: intent() } as never;
      throw new ApiError(404, "not found", {});
    });
    vi.mocked(fetchInvoiceTerms).mockResolvedValue(invoiceTerms as never);
    vi.mocked(payInvoice).mockResolvedValue({ payment: { id: "pay-2", redirect_url: "https://checkout.viva.example/2" } } as never);

    wrap(<PaymentFocusCard paymentId="pay-1" providers={[provider("other"), provider("box-k")]} preferred={null} />);

    expect(await screen.findByText("Η χρέωση της κάρτας ••4421 δεν έγινε.", { exact: false })).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("pay-other-card"));
    const sheet = await screen.findByTestId("pay-invoice-sheet");
    expect(await within(sheet).findByText("Επιτρέπω (κείμενο του API)")).toBeInTheDocument();
    const pay = within(sheet).getByTestId("pay-submit");
    expect(pay).toBeDisabled();
    fireEvent.click(within(sheet).getByTestId("pay-auto-yes"));
    fireEvent.click(pay);
    await waitFor(() =>
      expect(payInvoice).toHaveBeenCalledWith("access", "box-k", "inv-1", expect.objectContaining({ save_card: true, consent_accepted: true, autopay: true })),
    );
    await waitFor(() => expect(openCheckout).toHaveBeenCalled());
  });

  it("offers withdrawal within the 14 days and shows what comes back", async () => {
    vi.mocked(fetchPayment).mockResolvedValue({
      payment: intent({
        initiation: "payer",
        purpose_type: "membership_package",
        status: "succeeded",
        fulfilment_status: "done",
        declines: 0,
        succeeded_at: "2026-10-29T10:00:00Z",
        metadata: { withdrawal: { applies: true, deadline: "2099-11-12T10:00:00Z" } },
        description: "Unlimited",
      }),
    } as never);
    vi.mocked(withdrawPurchase).mockResolvedValue({ refund: {}, refunded_cents: 6000 } as never);

    wrap(<PaymentFocusCard paymentId="pay-1" providers={[provider("box-k")]} preferred="box-k" />);
    fireEvent.click(await screen.findByTestId("pay-withdraw"));
    fireEvent.click(await screen.findByTestId("pay-withdraw-confirm"));
    await waitFor(() => expect(withdrawPurchase).toHaveBeenCalledWith("access", "box-k", "pay-1"));
    expect(await screen.findByTestId("pay-withdrawn")).toHaveTextContent(/60,00/);
  });

  it("no withdrawal once the 14 days are over", async () => {
    vi.mocked(fetchPayment).mockResolvedValue({
      payment: intent({ initiation: "payer", purpose_type: "membership_package", status: "succeeded", fulfilment_status: "done", declines: 0, metadata: { withdrawal: { applies: true, deadline: "2001-01-01T00:00:00Z" } } }),
    } as never);
    wrap(<PaymentFocusCard paymentId="pay-1" providers={[provider("box-k")]} preferred="box-k" />);
    expect(await screen.findByTestId("pay-focus")).toBeInTheDocument();
    expect(screen.queryByTestId("pay-withdraw")).toBeNull();
  });
});

describe("saved cards and autopay (ADR-247)", () => {
  it("turns autopay on and removes a card after asking", async () => {
    vi.mocked(fetchSavedCards).mockResolvedValue({
      payment_methods: [
        { id: "card-1", provider: "viva", brand: "visa", last4: "4421", exp_month: 8, exp_year: 2028, status: "active", autopay: false, max_amount_cents: 7500, currency: "EUR" },
        { id: "card-0", provider: "viva", brand: "visa", last4: "0000", status: "revoked", autopay: false, max_amount_cents: 7500, currency: "EUR" },
      ],
    } as never);
    vi.mocked(setCardAutopay).mockResolvedValue({ payment_method: {} } as never);
    vi.mocked(removeSavedCard).mockResolvedValue({ payment_method: {} } as never);

    wrap(<SavedCardsCard slug="box-k" />);
    expect(await screen.findByText("Visa ••4421")).toBeInTheDocument();
    expect(screen.queryByText(/••0000/)).toBeNull();
    expect(screen.getByText("Λήγει 08/28")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("switch"));
    await waitFor(() => expect(setCardAutopay).toHaveBeenCalledWith("access", "box-k", "card-1", true));

    fireEvent.click(screen.getByTestId("pay-card-remove-card-1"));
    fireEvent.click(await screen.findByTestId("pay-card-remove-confirm"));
    await waitFor(() => expect(removeSavedCard).toHaveBeenCalledWith("access", "box-k", "card-1"));
  });

  it("is hidden without cards", async () => {
    vi.mocked(fetchSavedCards).mockResolvedValue({ payment_methods: [] } as never);
    const { container } = wrap(<SavedCardsCard slug="box-k" />);
    await waitFor(() => expect(fetchSavedCards).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
  });
});

describe("paying an open invoice (ADR-246)", () => {
  const invoices = [
    { id: "late", balance_due_cents: 7500, currency: "EUR", status: "issued", due_date: "2026-11-30", invoice_number: "INV-2", document_kind: "invoice", downloadable: false, total_cents: 7500 },
    { id: "first", balance_due_cents: 6000, currency: "EUR", status: "overdue", due_date: "2026-10-01", invoice_number: "INV-1", document_kind: "invoice", downloadable: false, total_cents: 6000 },
    { id: "paid", balance_due_cents: 0, currency: "EUR", status: "paid", due_date: "2026-09-01", invoice_number: "INV-0", document_kind: "invoice", downloadable: false, total_cents: 6000 },
  ];

  it("pays the invoice due first", () => {
    expect(nextOpenInvoice(invoices as never)?.id).toBe("first");
  });

  it("keeps «pay at the box» when online payment is off", async () => {
    vi.mocked(fetchInvoiceTerms).mockResolvedValue({ ...invoiceTerms, available: false } as never);
    wrap(<PayOpenInvoice provider={provider("box-k", { invoices } as never)} fallback={<p>στο box</p>} />);
    await waitFor(() => expect(fetchInvoiceTerms).toHaveBeenCalledWith("access", "box-k", "first", "el"));
    expect(screen.getByText("στο box")).toBeInTheDocument();
  });

  it("offers «Πληρωμή» when the box takes online payments", async () => {
    vi.mocked(fetchInvoiceTerms).mockResolvedValue(invoiceTerms as never);
    wrap(<PayOpenInvoice provider={provider("box-k", { invoices } as never)} fallback={<p>στο box</p>} />);
    fireEvent.click(await screen.findByTestId("pay-open-invoice"));
    expect(await screen.findByTestId("pay-invoice-sheet")).toHaveTextContent("Τιμολόγιο INV-1");
  });
});
