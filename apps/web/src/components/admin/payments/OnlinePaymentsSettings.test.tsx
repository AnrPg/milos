import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import el from "../../../../messages/el.json";
import { ApiError } from "@/api/client";
import type { PaymentAccount, PaymentAccountStatus } from "@/api/online-payments";

// Mockup s3, option B: one card with defaults in Ρυθμίσεις › Πληρωμές.

const nav = vi.hoisted(() => ({ params: "tab=payments", replace: vi.fn() }));
const api = vi.hoisted(() => ({
  fetchPaymentAccount: vi.fn(),
  startPaymentConnect: vi.fn(),
  savePaymentOptions: vi.fn(),
  savePaymentAccount: vi.fn(),
  disconnectPaymentAccount: vi.fn(),
}));
const settings = vi.hoisted(() => ({
  fetchAdminSettings: vi.fn(async () => ({ finance: { subscription_grace_days: 7 } })),
  updateAdminSettings: vi.fn(async (_token: string, body: { finance: { subscription_grace_days: number } }) => ({
    finance: { subscription_grace_days: body.finance.subscription_grace_days },
  })),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: nav.replace, push: vi.fn() }),
  useSearchParams: () => new URLSearchParams(nav.params),
  usePathname: () => "/admin/settings",
}));
vi.mock("@/api/online-payments", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/api/settings", async (original) => ({ ...(await original<object>()), ...settings }));

import { OnlinePaymentsSettings, onlineSentence } from "./OnlinePaymentsSettings";

const ACCOUNT: PaymentAccount = {
  id: "acc-1",
  provider: "viva",
  environment: "live",
  status: "active",
  settings: { source_code: "1234" },
  credentials_set: ["client_id", "client_secret", "merchant_id", "api_key"],
  webhook_url: "https://palee.app/api/webhooks/payments/org/acc-1",
  options: {
    purposes: { packages: true, autopay: true, drop_in: true, shop: true, personal_training: true },
    notify_member: true,
    notify_staff: true,
  },
  connection: "keys",
};

function status(account: PaymentAccount | null, connect: string[] = ["stripe"]): PaymentAccountStatus {
  return { account, providers: ["viva", "stripe"], environments: ["test", "live"], connect_providers: { live: connect, test: [] } };
}

function wrap(locale: "en" | "el" = "en") {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale={locale} messages={locale === "en" ? en : el}>
        <OnlinePaymentsSettings token="token" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("OnlinePaymentsSettings", () => {
  beforeEach(() => {
    nav.params = "tab=payments";
    nav.replace.mockClear();
    Object.values(api).forEach((mock) => mock.mockReset());
    settings.updateAdminSettings.mockClear();
  });

  it("offers one card before connecting and asks Viva for its keys when it has no one-button connect", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(null));
    wrap();

    expect(await screen.findByText("Take cards in the app and on the buy page")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Connect with Viva" }));

    expect(screen.getByText("Connect Viva with its API keys")).toBeVisible();
    expect(screen.getByLabelText("Merchant ID")).toBeVisible();
    expect(api.startPaymentConnect).not.toHaveBeenCalled();
  });

  it("sends the owner to the provider page for a one-button provider", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(null));
    api.startPaymentConnect.mockResolvedValue({ url: "https://connect.stripe.com/oauth/authorize?state=x" });
    const assign = vi.fn();
    vi.stubGlobal("location", { ...window.location, assign });
    wrap();

    fireEvent.click(await screen.findByRole("button", { name: "Stripe" }));

    expect(await screen.findByText("Taking you to Stripe")).toBeVisible();
    await waitFor(() => expect(assign).toHaveBeenCalledWith("https://connect.stripe.com/oauth/authorize?state=x"));
    expect(api.startPaymentConnect).toHaveBeenCalledWith("token", "stripe", "live");
    vi.unstubAllGlobals();
  });

  it("says in plain words why the connection did not finish and clears the code from the address", async () => {
    nav.params = "tab=payments&connect=access_denied";
    api.fetchPaymentAccount.mockResolvedValue(status(null));
    wrap();

    expect(await screen.findByText("You cancelled on the provider's page. Nothing changed.")).toBeVisible();
    expect(nav.replace).toHaveBeenCalledWith("/admin/settings?tab=payments", { scroll: false });
  });

  it("shows the provider and one sentence, and «Αλλαγή» opens the five switches", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(ACCOUNT));
    api.savePaymentOptions.mockImplementation(async (_token: string, update: { purposes: Record<string, boolean> }) =>
      status({ ...ACCOUNT, options: { ...ACCOUNT.options, purposes: { ...ACCOUNT.options.purposes, ...update.purposes } } }),
    );
    wrap("el");

    expect(await screen.findByText("Συνδεδεμένο με Viva")).toBeVisible();
    expect(screen.getByText(/Ενεργό/)).toBeVisible();
    expect(screen.getByTestId("online-sentence")).toHaveTextContent(
      "Τα μέλη box πληρώνουν online πακέτα συνδρομής, μία επίσκεψη και δοκιμαστικό στην κράτηση, κατάστημα και πακέτα προσωπικών προπονήσεων. Οι ανανεώσεις γίνονται αυτόματα με την κάρτα τους.",
    );

    fireEvent.click(screen.getByRole("button", { name: "Αλλαγή" }));
    expect(screen.getAllByRole("switch")).toHaveLength(5);
    fireEvent.click(screen.getByRole("switch", { name: "Κατάστημα" }));
    await waitFor(() => expect(api.savePaymentOptions).toHaveBeenCalledWith("token", { purposes: { shop: false } }));
    fireEvent.click(screen.getByRole("button", { name: "Τέλος" }));
    expect(await screen.findByTestId("online-sentence")).not.toHaveTextContent("κατάστημα");
  });

  it("keeps the failure policy under «Προχωρημένα» and edits the Finance grace days", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(ACCOUNT));
    api.savePaymentOptions.mockResolvedValue(status({ ...ACCOUNT, options: { ...ACCOUNT.options, notify_member: false } }));
    wrap("el");

    fireEvent.click(await screen.findByRole("button", { name: /Προχωρημένα/ }));
    expect(screen.getByText("3 φορές: σε 1, 3 και 7 ημέρες")).toBeVisible();

    fireEvent.click(screen.getByRole("switch", { name: "Ειδοποίηση μέλους" }));
    await waitFor(() => expect(api.savePaymentOptions).toHaveBeenCalledWith("token", { notify_member: false }));

    const grace = await screen.findByRole("combobox", { name: "Περίοδος χάριτος" });
    expect(grace).toHaveTextContent("7 ημέρες");
    const { chooseOption } = await import("@/components/ui/select-test-utils");
    chooseOption(grace, "14 ημέρες");
    await waitFor(() =>
      expect(settings.updateAdminSettings).toHaveBeenCalledWith("token", { finance: { subscription_grace_days: 14 } }),
    );
  });

  it("asks before disconnecting", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(ACCOUNT));
    api.disconnectPaymentAccount.mockResolvedValue(status({ ...ACCOUNT, status: "disabled" }));
    wrap("el");

    fireEvent.click(await screen.findByRole("button", { name: /Προχωρημένα/ }));
    fireEvent.click(screen.getByRole("button", { name: "Αποσύνδεση" }));
    const dialog = screen.getByRole("dialog", { name: "Αποσύνδεση από Viva;" });
    expect(within(dialog).getByText("Οι αποθηκευμένες κάρτες σταματούν να χρεώνονται.")).toBeVisible();
    fireEvent.click(within(dialog).getByRole("button", { name: "Αποσύνδεση" }));

    await waitFor(() => expect(api.disconnectPaymentAccount).toHaveBeenCalledWith("token"));
    expect(await screen.findByText("Δέξου κάρτες στο app και στη σελίδα αγοράς")).toBeVisible();
  });

  it("keeps saved keys write-only and shows the provider's refusal inside the form", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(ACCOUNT));
    api.savePaymentAccount.mockRejectedValue(
      new ApiError(422, "validation_failed", { code: "validation_failed", errors: { credentials: ["rejected"] } }),
    );
    wrap();

    fireEvent.click(await screen.findByRole("button", { name: /Advanced/ }));
    const form = screen.getByRole("form", { name: "API keys" });
    expect(within(form).getByLabelText("API key")).toHaveAttribute("placeholder", "Saved · leave empty to keep it");
    expect(within(form).getByLabelText("API key")).toHaveValue("");
    fireEvent.change(within(form).getByLabelText("API key"), { target: { value: "new-key" } });
    fireEvent.click(within(form).getByRole("button", { name: "Check and save" }));

    expect(await within(form).findByText(/Viva did not accept these keys/)).toBeVisible();
    expect(api.savePaymentAccount).toHaveBeenCalledWith("token", {
      provider: "viva",
      environment: "live",
      credentials: { api_key: "new-key" },
      settings: { source_code: "1234" },
    });
  });

  it("marks a missing key under its field", async () => {
    api.fetchPaymentAccount.mockResolvedValue(status(null, []));
    api.savePaymentAccount.mockRejectedValue(
      new ApiError(422, "validation_failed", { code: "validation_failed", errors: { merchant_id: ["required"] } }),
    );
    wrap();

    fireEvent.click(await screen.findByRole("button", { name: "Connect with Viva" }));
    fireEvent.click(screen.getByRole("button", { name: "Check and save" }));
    const field = screen.getByLabelText("Merchant ID");
    await waitFor(() => expect(field).toHaveAttribute("aria-invalid", "true"));
    expect(screen.getByText("Fill this in.")).toBeVisible();
  });
});

describe("onlineSentence", () => {
  const t = (key: string, values?: Record<string, string>) =>
    (en.OnlinePayments as Record<string, string>)[key].replace("{list}", values?.list ?? "");

  it("says when renewals need their own payment and when nothing is paid online", () => {
    expect(
      onlineSentence({ packages: false, autopay: false, drop_in: false, shop: false, personal_training: false }, t, "en"),
    ).toBe("Box members pay for nothing online. Renewals need a payment of their own.");
  });
});
