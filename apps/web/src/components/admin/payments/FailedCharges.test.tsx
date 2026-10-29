import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";
import type { FailedCharge } from "@/api/online-payments";

// Mockup s3 B: failed saved-card charges that need a person, in Οικονομικά › Εκκρεμότητες.

const api = vi.hoisted(() => ({ actOnFailedCharge: vi.fn() }));
vi.mock("@/api/online-payments", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/lib/organization-slug", async (original) => ({
  ...(await original<object>()),
  useOrganizationTimeZone: () => "Europe/Athens",
}));

import { formatInZone } from "@/lib/zoned-time";

import { FailedChargesList, nextStepText } from "./FailedCharges";

const at = (iso: string) => formatInZone(iso, "Europe/Athens", "el", "time");

const t = (key: string, values?: Record<string, string | number>) =>
  Object.entries(values ?? {}).reduce(
    (text, [name, value]) => text.replace(`{${name}}`, String(value)),
    (el.OnlinePayments as Record<string, string>)[key],
  );

const charge = (extra: Partial<FailedCharge> = {}): FailedCharge => ({
  id: "c1",
  member_name: "Ελένη Νικολάου",
  purpose_type: "finance_invoice",
  amount_cents: 7500,
  currency: "EUR",
  description: "Πακέτο συνδρομής «Unlimited»",
  status: "scheduled",
  failure_code: "insufficient_funds",
  next_attempt_at: "2026-10-30T04:00:00Z",
  declines: 2,
  retries: 3,
  ...extra,
});

function wrap(charges: FailedCharge[], canRetry = true) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        <FailedChargesList token="token" charges={charges} loading={false} canRetry={canRetry} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("nextStepText", () => {
  // 29 Oct 2026, 15:00 in Athens (UTC+2 after the clocks go back).
  const now = new Date("2026-10-29T13:00:00Z");

  it("names the next try on the gym's clock with which try it is", () => {
    expect(nextStepText(charge(), t, "el", "Europe/Athens", now)).toBe(
      `Νέα προσπάθεια αύριο ${at("2026-10-30T04:00:00Z")} (2 από 3)`,
    );
    expect(at("2026-10-30T04:00:00Z")).toMatch(/^06:00/);
    expect(nextStepText(charge({ next_attempt_at: "2026-10-29T20:00:00Z", declines: 1 }), t, "el", "Europe/Athens", now)).toBe(
      `Νέα προσπάθεια σήμερα ${at("2026-10-29T20:00:00Z")} (1 από 3)`,
    );
  });

  it("uses the gym's day, not UTC's: 23:30 UTC on the 29th is the 30th in Athens", () => {
    const late = new Date("2026-10-29T21:30:00Z");
    expect(nextStepText(charge({ next_attempt_at: "2026-10-29T23:30:00Z" }), t, "el", "Europe/Athens", late)).toBe(
      `Νέα προσπάθεια αύριο ${at("2026-10-29T23:30:00Z")} (2 από 3)`,
    );
  });

  it("waits for the member once no try is left", () => {
    expect(nextStepText(charge({ status: "failed", next_attempt_at: null, declines: 3 }), t, "el", "Europe/Athens", now)).toBe(
      "Περιμένουμε νέα κάρτα από το μέλος",
    );
  });
});

describe("FailedChargesList", () => {
  beforeEach(() => api.actOnFailedCharge.mockReset());

  it("shows who, what, why and the three actions", () => {
    wrap([charge()]);
    const row = screen.getByTestId("failed-charge");
    expect(within(row).getByText("Ελένη Νικολάου")).toBeVisible();
    expect(within(row).getByText(/Πακέτο συνδρομής «Unlimited» · 75,00/)).toBeVisible();
    expect(within(row).getByText("Ανεπαρκές υπόλοιπο")).toBeVisible();
    expect(within(row).getByRole("button", { name: "Νέα προσπάθεια" })).toBeVisible();
    expect(within(row).getByRole("button", { name: "Σύνδεσμος για νέα κάρτα" })).toBeVisible();
    expect(within(row).getByRole("button", { name: "Πληρώθηκε στο ταμείο" })).toBeVisible();
  });

  it("closes a charge paid at the desk", async () => {
    api.actOnFailedCharge.mockResolvedValue({ payment: charge({ status: "failed" }) });
    wrap([charge()]);
    fireEvent.click(screen.getByRole("button", { name: "Πληρώθηκε στο ταμείο" }));

    await waitFor(() => expect(api.actOnFailedCharge).toHaveBeenCalledWith("token", "c1", "dismiss"));
    const row = screen.getByTestId("failed-charge");
    expect(await within(row).findByText(/Έγινε/)).toBeVisible();
    expect(within(row).queryByRole("button")).toBeNull();
  });

  it("sends the card link and says so", async () => {
    api.actOnFailedCharge.mockResolvedValue({ payment: charge() });
    wrap([charge()]);
    fireEvent.click(screen.getByRole("button", { name: "Σύνδεσμος για νέα κάρτα" }));
    expect(await screen.findByText("Στάλθηκε σύνδεσμος αλλαγής κάρτας")).toBeVisible();
    expect(api.actOnFailedCharge).toHaveBeenCalledWith("token", "c1", "card-link");
  });

  it("keeps the actions when a new try is declined again", async () => {
    api.actOnFailedCharge.mockResolvedValue({ payment: charge({ status: "failed" }) });
    wrap([charge()]);
    fireEvent.click(screen.getByRole("button", { name: "Νέα προσπάθεια" }));
    expect(await screen.findByText("Απορρίφθηκε ξανά")).toBeVisible();
    expect(screen.getByRole("button", { name: "Σύνδεσμος για νέα κάρτα" })).toBeVisible();
  });

  it("hides «Νέα προσπάθεια» from staff who only take payments", () => {
    wrap([charge()], false);
    expect(screen.queryByRole("button", { name: "Νέα προσπάθεια" })).toBeNull();
  });

  it("says when nothing needs a person", () => {
    wrap([]);
    expect(screen.getByText("Καμία αποτυχημένη χρέωση δεν σε χρειάζεται.")).toBeVisible();
  });
});
