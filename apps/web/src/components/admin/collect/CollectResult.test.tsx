import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";
import en from "../../../../messages/en.json";
import { ApiError } from "@/api/client";
import type { TerminalPayment } from "@/api/desk-collect";

// Mockup pilot-gaps screen 2 A, «Αποτέλεσμα» (ADR-264, ADR-272).

const api = vi.hoisted(() => ({ emailTerminalReceipt: vi.fn(), fetchTerminalPayment: vi.fn() }));
vi.mock("@/api/desk-collect", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" }, currentUser: { id: "me" } }),
}));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => null, adminHref: (href: string) => href }));
vi.mock("@/components/referrals/QrCode", () => ({
  QrCode: ({ value, label }: { value: string; label: string }) => <img alt={label} data-value={value} />,
}));

import { CollectResult } from "./CollectResult";

function payment(overrides: Partial<TerminalPayment> = {}): TerminalPayment {
  return {
    id: "pi-1",
    provider: "viva",
    environment: "live",
    user_id: null,
    initiation: "terminal",
    purpose_type: "free_sale",
    purpose_id: "fs-1",
    amount_cents: 9000,
    currency: "EUR",
    description: "Day pass",
    status: "succeeded",
    fulfilment_status: "fulfilled",
    refunded_cents: 0,
    declines: 0,
    retries: 0,
    reference: "pt1.ref",
    card_brand: "visa",
    card_last4: "4421",
    succeeded_at: "2026-10-29T07:02:00Z",
    failure_code: null,
    tip_cents: 500,
    surcharge_cents: 180,
    started_on: "phone",
    tip_attribution: "started_payment",
    tip_recipient_user_id: "me",
    document: {
      id: "doc-1",
      kind: "receipt",
      number: "R-000420",
      gross_cents: 9180,
      currency: "EUR",
      issued_at: "2026-10-29T07:02:05Z",
      authority: "mydata",
      transmission_status: "pending",
      receipt_url: "https://palee.app/api/public/receipts/token",
    },
    ...overrides,
  } as TerminalPayment;
}

function wrap(value: TerminalPayment, locale: "en" | "el" = "en", handlers: Partial<Record<"onNew" | "onAgain" | "onDone" | "onChange", () => void>> = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale={locale} messages={locale === "en" ? en : el}>
        <CollectResult
          payment={value}
          payerName={value.user_id ? "Μαρία Κωνσταντίνου" : null}
          onChange={handlers.onChange ?? vi.fn()}
          onAgain={handlers.onAgain ?? vi.fn()}
          onNew={handlers.onNew ?? vi.fn()}
          onDone={handlers.onDone ?? vi.fn()}
        />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("CollectResult", () => {
  beforeEach(() => {
    Object.values(api).forEach((mock) => mock.mockReset());
  });

  it("shows what the card paid, the surcharge on the receipt and the tip for me apart", () => {
    wrap(payment());
    expect(screen.getByText("€96.80 paid")).toBeTruthy();
    expect(screen.getByText("Visa ••4421 · Viva · " + new Intl.DateTimeFormat("en", { hour: "2-digit", minute: "2-digit" }).format(new Date("2026-10-29T07:02:00Z")))).toBeTruthy();
    expect(screen.getByText("Card surcharge · on the receipt")).toBeTruthy();
    expect(screen.getByTestId("collect-tip-owner").textContent).toBe("Tip · for you, not on the receipt");
    expect(screen.getByTestId("collect-receipt-title").textContent).toBe("Receipt R-000420 · €91.80");
    expect(screen.getByText("Retail customer · Card (Tap to Pay)")).toBeTruthy();
    expect(screen.getByTestId("collect-tx").textContent).toBe("Transmission pending");
  });

  it("shows a walk-in the receipt QR by default and emails it to the address typed", async () => {
    api.emailTerminalReceipt.mockResolvedValue({ email: { id: "e-1" } });
    wrap(payment());
    expect(screen.getByAltText("Receipt QR code").getAttribute("data-value")).toBe("https://palee.app/api/public/receipts/token");
    fireEvent.click(screen.getByTestId("collect-send-email"));
    fireEvent.click(screen.getByTestId("collect-email-send"));
    expect(await screen.findByText("Enter a valid email.")).toBeTruthy();
    expect(api.emailTerminalReceipt).not.toHaveBeenCalled();
    fireEvent.change(screen.getByTestId("collect-email-to"), { target: { value: "walkin@example.com" } });
    fireEvent.click(screen.getByTestId("collect-email-send"));
    await waitFor(() => expect(screen.getByTestId("collect-email-sent")).toBeTruthy());
    expect(api.emailTerminalReceipt).toHaveBeenCalledWith("token", "pi-1", expect.stringMatching(/^collect-/), "walkin@example.com");
  });

  it("emails a member's receipt to their account, and asks for an address when there is none", async () => {
    api.emailTerminalReceipt.mockRejectedValueOnce(new ApiError(422, "Enter an email address", { code: "no_recipient" }));
    wrap(payment({ user_id: "u-maria", tip_cents: 0, surcharge_cents: 0, tip_attribution: null, tip_recipient_user_id: null }), "el");
    expect(screen.queryByTestId("collect-breakdown")).toBeNull();
    expect(screen.queryByTestId("collect-qr")).toBeNull();
    expect(screen.getByText("Μαρία Κωνσταντίνου · Κάρτα (Tap to Pay)")).toBeTruthy();
    fireEvent.click(screen.getByTestId("collect-send-email"));
    fireEvent.click(screen.getByTestId("collect-email-send"));
    expect(await screen.findByText("Δεν έχει email στον λογαριασμό του. Γράψε ένα.")).toBeTruthy();
    expect(api.emailTerminalReceipt).toHaveBeenCalledWith("token", "pi-1", expect.any(String), undefined);
    expect(screen.getByTestId("collect-email-to")).toBeTruthy();
  });

  it("names the front desk when the tip is the role's", () => {
    wrap(payment({ tip_attribution: "front_desk_role", tip_recipient_user_id: null }), "el");
    expect(screen.getByTestId("collect-tip-owner").textContent).toBe("Φιλοδώρημα · για την υποδοχή, όχι στην απόδειξη");
  });

  it("says «Μην χρεώσεις ξανά» while Viva has not confirmed, and checks again", async () => {
    const onChange = vi.fn();
    api.fetchTerminalPayment.mockResolvedValue({ payment: payment() });
    wrap(payment({ status: "awaiting_payer", failure_code: "terminal_unconfirmed", document: null }), "el", { onChange });
    expect(screen.getByText("Περιμένουμε τη Viva")).toBeTruthy();
    expect(screen.getByText("Μην χρεώσεις ξανά.")).toBeTruthy();
    fireEvent.click(screen.getByTestId("collect-check-now"));
    await waitFor(() => expect(onChange).toHaveBeenCalled());
  });

  it("explains a declined card, a cancel and a mismatched amount", () => {
    const { unmount } = wrap(payment({ status: "failed", failure_code: "terminal_declined", document: null }), "el");
    expect(screen.getByText("Η κάρτα απορρίφθηκε")).toBeTruthy();
    expect(screen.getByText("Ξανά με άλλη κάρτα")).toBeTruthy();
    unmount();
    const cancelled = wrap(payment({ status: "cancelled", failure_code: "terminal_cancelled", document: null }), "el");
    expect(screen.getByText("Ακυρώθηκε στη Viva")).toBeTruthy();
    cancelled.unmount();
    wrap(payment({ status: "failed", failure_code: "amount_mismatch", document: null }), "en");
    expect(screen.getByText("Viva's amount doesn't match")).toBeTruthy();
    expect(screen.getByText(/other than €90.00/)).toBeTruthy();
  });

  it("waits for the receipt when it is not issued yet", () => {
    wrap(payment({ document: null }));
    expect(screen.getByTestId("collect-receipt-preparing").textContent).toContain("The receipt is being prepared.");
  });
});
