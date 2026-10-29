import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import { ApiError } from "@/api/client";
import { chooseValue } from "@/components/ui/select-test-utils";

// Mockup s1, option C: the billing details as a four-row checklist with panels.

const GR = {
  country: "GR",
  currency: "EUR",
  languages: ["el", "en"],
  tax_system: "vat" as const,
  authority: "mydata" as const,
  register: "standard" as const,
  till_device: "none" as const,
  einvoicing: [],
  required_fields: ["legal_name", "street", "postal_code", "city", "tax_id", "tax_office"],
  tax_categories: ["standard"],
  tax_office: true,
  retention_years: 5,
};
const CY = { ...GR, country: "CY", authority: "none" as const, required_fields: ["legal_name", "street", "postal_code", "city", "tax_id"], tax_office: false };

const identity = (fields: Record<string, unknown>) => ({
  id: "identity-1",
  country_code: "GR",
  currency: "EUR",
  vat_scheme: "standard",
  branch_code: 0,
  fiscal_year_start_month: 1,
  ...fields,
});

const api = vi.hoisted(() => ({
  fetchFiscalIdentity: vi.fn(),
  fetchFiscalCountries: vi.fn(),
  saveFiscalIdentity: vi.fn(),
  fetchAuthorityConnection: vi.fn(),
}));

vi.mock("@/api/fiscal", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => null, adminHref: (href: string) => href }));

import { FiscalIdentitySettings } from "./FiscalIdentitySettings";

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        <FiscalIdentitySettings />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("FiscalIdentitySettings", () => {
  beforeEach(() => {
    Object.values(api).forEach((mock) => mock.mockReset());
    api.fetchFiscalCountries.mockResolvedValue({ countries: [CY, GR], vat_schemes: ["standard", "small_business", "exempt"] });
    api.fetchAuthorityConnection.mockResolvedValue({ connection: null, environments: ["sandbox", "test", "production"] });
  });

  it("starts with the country and keeps the other rows locked until it is chosen", async () => {
    api.fetchFiscalIdentity.mockResolvedValue({ identity: null, profile: null, missing: ["country_code"], complete: false });
    api.saveFiscalIdentity.mockResolvedValue({ identity: identity({}), profile: GR, missing: ["legal_name", "street", "postal_code", "city", "tax_id", "tax_office"], complete: false });
    wrap();

    const country = await screen.findByTestId("fiscal-row-country");
    expect(country).toHaveAttribute("data-state", "next");
    expect(screen.getByTestId("fiscal-row-business")).toBeDisabled();
    expect(screen.getByTestId("fiscal-row-business")).toHaveTextContent(en.FiscalIdentity.afterCountry);
    expect(screen.getByRole("img", { name: "0% complete" })).toBeInTheDocument();

    fireEvent.click(country);
    const panel = await screen.findByTestId("fiscal-country-panel");
    fireEvent.click(within(panel).getByTestId("fiscal-country-GR"));
    fireEvent.click(within(panel).getByTestId("fiscal-country-done"));

    await waitFor(() => expect(api.saveFiscalIdentity).toHaveBeenCalledWith("token", { country_code: "GR" }));
    await waitFor(() => expect(screen.getByTestId("fiscal-row-business")).toBeEnabled());
    expect(screen.getByTestId("fiscal-row-business")).toHaveAttribute("data-state", "next");
    expect(screen.getByTestId("fiscal-row-business")).toHaveTextContent("Legal name, Tax ID (ΑΦΜ), Tax office (ΔΟΥ)");
  });

  it("saves one row's fields and shows a wrong field under it, inside the panel", async () => {
    api.fetchFiscalIdentity.mockResolvedValue({ identity: identity({}), profile: GR, missing: ["legal_name", "tax_id", "tax_office"], complete: false });
    api.saveFiscalIdentity.mockRejectedValueOnce(new ApiError(422, "invalid", { code: "validation_failed", errors: { tax_id: ["check_digit"] } }));
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-row-business"));
    const panel = await screen.findByTestId("fiscal-panel-business");
    fireEvent.change(within(panel).getByTestId("fiscal-field-legal_name"), { target: { value: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε." } });
    fireEvent.change(within(panel).getByTestId("fiscal-field-tax_id"), { target: { value: "801234568" } });
    fireEvent.change(within(panel).getByTestId("fiscal-field-tax_office"), { target: { value: "Ζ΄ Αθηνών" } });
    fireEvent.click(within(panel).getByTestId("fiscal-panel-save"));

    await within(panel).findByText(en.FiscalIdentity.reason.check_digit);
    expect(within(panel).getByTestId("fiscal-field-tax_id")).toHaveAttribute("aria-invalid", "true");
    expect(api.saveFiscalIdentity).toHaveBeenCalledWith("token", {
      legal_name: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.",
      trade_name: null,
      tax_id: "801234568",
      tax_office: "Ζ΄ Αθηνών",
    });
  });

  it("fills the Greek VAT number from the ΑΦΜ when the tax row is saved", async () => {
    api.fetchFiscalIdentity.mockResolvedValue({ identity: identity({ tax_id: "801234567" }), profile: GR, missing: ["legal_name"], complete: false });
    api.saveFiscalIdentity.mockImplementation(async () => ({ identity: identity({ tax_id: "801234567" }), profile: GR, missing: ["legal_name"], complete: false }));
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-row-tax"));
    const panel = await screen.findByTestId("fiscal-panel-tax");
    expect(within(panel).getByText("The VAT number is filled in by itself: EL801234567.")).toBeInTheDocument();
    chooseValue(within(panel).getByTestId("fiscal-field-vat_scheme"), "standard");
    fireEvent.click(within(panel).getByTestId("fiscal-panel-save"));

    await waitFor(() => expect(api.saveFiscalIdentity).toHaveBeenCalled());
    expect(api.saveFiscalIdentity.mock.calls[0][1]).toMatchObject({ vat_scheme: "standard", vat_number: "EL801234567", branch_code: 0 });
  });

  it("says when the details are complete and shows the myDATA connection", async () => {
    api.fetchFiscalIdentity.mockResolvedValue({
      identity: identity({ legal_name: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.", tax_id: "801234567", tax_office: "Ζ΄ Αθηνών", street: "Φωκίωνος Νέγρη 12", postal_code: "11361", city: "Αθήνα" }),
      profile: GR,
      missing: [],
      complete: true,
    });
    api.fetchAuthorityConnection.mockResolvedValue({
      connection: { authority: "mydata", environment: "production", status: "active", has_subscription_key: true },
      environments: ["sandbox", "test", "production"],
    });
    wrap();

    expect(await screen.findByTestId("fiscal-identity-ready")).toHaveTextContent(en.FiscalIdentity.ready);
    expect(screen.getByRole("img", { name: "100% complete" })).toBeInTheDocument();
    expect(screen.getByTestId("fiscal-row-business")).toHaveTextContent("ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε. · 801234567 · Ζ΄ Αθηνών");
    expect(await screen.findByTestId("fiscal-mydata-status")).toHaveTextContent(en.FiscalIdentity.next.connected);
    expect(screen.getByTestId("fiscal-next-step")).toHaveTextContent("Active (production)");
  });

  it("says a country without a tax authority needs no further step", async () => {
    api.fetchFiscalIdentity.mockResolvedValue({ identity: identity({ country_code: "CY", legal_name: "Kypseli Ltd" }), profile: CY, missing: [], complete: true });
    wrap();

    expect(await screen.findByTestId("fiscal-next-step")).toHaveTextContent(en.FiscalIdentity.next.noneTitle);
    expect(api.fetchAuthorityConnection).not.toHaveBeenCalled();
  });
});
