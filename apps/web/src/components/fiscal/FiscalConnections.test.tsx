import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import { ApiError } from "@/api/client";

// Mockup p3, alternative A (ADR-273): the «Συνδέσεις» card and its side panel.

const api = vi.hoisted(() => ({
  fetchFiscalConnections: vi.fn(),
  saveFiscalConnection: vi.fn(),
  checkFiscalConnection: vi.fn(),
}));

vi.mock("@/api/fiscal", async (original) => ({ ...(await original<object>()), ...api }));

import { FiscalConnectionsCard } from "./FiscalConnections";
import { apiEnvironment, draftOf, saveBody } from "./connections-model";

const mydata = {
  authority: "mydata",
  environment: "production",
  user_id: "kypseli_box",
  has_subscription_key: true,
  status: "active",
  error_code: null,
  checked_at: "2026-10-29T12:32:00Z",
  updated_at: "2026-10-29T12:32:00Z",
  updated_by_platform: false,
  updated_by_name: "Apostolos",
};

const overview = (connections: Record<string, unknown>, extra: Record<string, unknown> = {}) => ({
  country: "GR",
  kinds: ["mydata", "registry"],
  managed_by: "owner",
  connections: { mydata: null, registry: null, ...connections },
  ...extra,
});

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
        <FiscalConnectionsCard token="token" countryName="Greece" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

async function openPanel(kind: string) {
  fireEvent.click(await screen.findByTestId(`fiscal-connection-${kind}`));
  return screen.findByTestId(`fiscal-connection-panel-${kind}`);
}

describe("FiscalConnectionsCard", () => {
  beforeEach(() => {
    Object.values(api).forEach((mock) => mock.mockReset());
  });

  it("lists only the country's connections, each with its status", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata }));
    wrap();

    expect(await screen.findByTestId("fiscal-connection-mydata-status")).toHaveTextContent(en.FiscalConnections.status.active);
    expect(screen.getByTestId("fiscal-connection-registry-status")).toHaveTextContent(en.FiscalConnections.status.none);
    expect(screen.getByTestId("fiscal-connection-registry")).toHaveTextContent(en.FiscalConnections.registryName);
    expect(screen.queryByTestId("fiscal-connection-tse")).toBeNull();
  });

  it("shows a saved secret only as «Saved» and sends it only when replaced", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata }));
    api.saveFiscalConnection.mockResolvedValue({ connection: mydata, check: { result: "ok", error_code: null, detail: {} } });
    wrap();

    const panel = await openPanel("mydata");
    const key = within(panel).getByTestId("fiscal-connection-subscription_key");
    expect(key).toHaveAttribute("data-saved", "true");
    expect(key).toHaveTextContent(en.FiscalConnections.secret.saved);
    expect(within(panel).getByTestId("fiscal-connection-updated")).toHaveTextContent("Apostolos");

    // Saving without replacing keeps the saved key.
    fireEvent.click(within(panel).getByTestId("fiscal-connection-save"));
    await waitFor(() => expect(api.saveFiscalConnection).toHaveBeenCalledTimes(1));
    expect(api.saveFiscalConnection.mock.calls[0][1]).toBe("mydata");
    expect(api.saveFiscalConnection.mock.calls[0][2]).toEqual({ environment: "production", user_id: "kypseli_box" });
    expect(await within(panel).findByTestId("fiscal-connection-saved")).toHaveTextContent(en.FiscalConnections.saved);

    // «Replace» opens an empty field; the new key is sent.
    fireEvent.click(within(panel).getByTestId("fiscal-connection-subscription_key-replace"));
    fireEvent.change(within(panel).getByTestId("fiscal-connection-subscription_key"), { target: { value: "new-key" } });
    fireEvent.click(within(panel).getByTestId("fiscal-connection-save"));
    await waitFor(() => expect(api.saveFiscalConnection).toHaveBeenCalledTimes(2));
    expect(api.saveFiscalConnection.mock.calls[1][2]).toMatchObject({ subscription_key: "new-key" });
  });

  it("shows a refused key under its field, inside the panel", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({}));
    api.saveFiscalConnection.mockResolvedValue({
      connection: { ...mydata, status: "invalid", error_code: "credentials_rejected" },
      check: { result: "invalid", error_code: "credentials_rejected", detail: {} },
    });
    wrap();

    const panel = await openPanel("mydata");
    fireEvent.change(within(panel).getByTestId("fiscal-connection-user_id"), { target: { value: "kypseli_box" } });
    fireEvent.change(within(panel).getByTestId("fiscal-connection-subscription_key"), { target: { value: "bad-key" } });
    fireEvent.click(within(panel).getByTestId("fiscal-connection-save"));

    expect(await within(panel).findByText(en.FiscalConnections.error.credentials_rejected_aade)).toBeInTheDocument();
    expect(within(panel).getByTestId("fiscal-connection-subscription_key")).toHaveAttribute("aria-invalid", "true");
    expect(within(panel).queryByTestId("fiscal-connection-saved")).toBeNull();
  });

  it("puts the API's field errors under the fields", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({}));
    api.saveFiscalConnection.mockRejectedValue(
      new ApiError(422, "invalid", { code: "validation_failed", errors: { user_id: ["required"], subscription_key: ["required"] } }),
    );
    wrap();

    const panel = await openPanel("mydata");
    fireEvent.click(within(panel).getByTestId("fiscal-connection-save"));

    await waitFor(() => expect(within(panel).getByTestId("fiscal-connection-user_id")).toHaveAttribute("aria-invalid", "true"));
    expect(within(panel).getByTestId("fiscal-connection-subscription_key")).toHaveAttribute("aria-invalid", "true");
  });

  it("runs «Connection test» and says what AADE found for the registry", async () => {
    const registry = { environment: "sandbox", username: null, has_password: false, status: "active", updated_by_platform: false };
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata, registry }));
    api.checkFiscalConnection.mockResolvedValue({
      connection: registry,
      check: { result: "ok", error_code: null, detail: { tax_id: "801234567", legal_name: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε." } },
    });
    wrap();

    const panel = await openPanel("registry");
    expect(within(panel).getByText(en.FiscalConnections.check.registryHint)).toBeInTheDocument();
    fireEvent.click(within(panel).getByTestId("fiscal-connection-check"));

    expect(await within(panel).findByTestId("fiscal-connection-check-result")).toHaveTextContent(
      "AADE found 801234567: ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.",
    );
    expect(api.checkFiscalConnection).toHaveBeenCalledWith("token", "registry");
  });

  it("explains a check that came too soon", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata }));
    api.checkFiscalConnection.mockRejectedValue(new ApiError(429, "too soon", { code: "check_too_soon" }));
    wrap();

    const panel = await openPanel("mydata");
    fireEvent.click(within(panel).getByTestId("fiscal-connection-check"));
    expect(await within(panel).findByTestId("fiscal-connection-check-result")).toHaveTextContent(en.FiscalConnections.error.check_too_soon);
  });

  it("cannot test a connection that is not saved yet", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({}));
    wrap();

    const panel = await openPanel("registry");
    expect(within(panel).getByTestId("fiscal-connection-check")).toBeDisabled();
    expect(within(panel).getByText(en.FiscalConnections.check.needsSave)).toBeInTheDocument();
  });

  it("explains an invalid connection with its error code", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata: { ...mydata, status: "invalid", error_code: "credentials_rejected" } }));
    wrap();

    const panel = await openPanel("mydata");
    expect(within(panel).getByTestId("fiscal-connection-invalid")).toHaveTextContent(en.FiscalConnections.error.credentials_rejected_aade);
    expect(within(panel).getByTestId("fiscal-connection-invalid")).toHaveTextContent(en.FiscalConnections.waiting);
  });

  it("is read-only while the Palee team manages the connections", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata: { ...mydata, updated_by_platform: true, updated_by_name: null } }, { managed_by: "palee" }));
    wrap();

    expect(await screen.findByTestId("fiscal-connections-managed")).toHaveTextContent(en.FiscalConnections.managedByPalee);
    const panel = await openPanel("mydata");
    expect(within(panel).getByTestId("fiscal-connection-managed")).toBeInTheDocument();
    expect(within(panel).queryByTestId("fiscal-connection-save")).toBeNull();
    expect(within(panel).getByTestId("fiscal-connection-user_id")).toBeDisabled();
    expect(within(panel).queryByTestId("fiscal-connection-subscription_key-replace")).toBeNull();
    expect(within(panel).getByTestId("fiscal-connection-updated")).toHaveTextContent("Palee team");
    // «Connection test» stays available.
    expect(within(panel).getByTestId("fiscal-connection-check")).toBeEnabled();
  });

  it("keeps the environment under Advanced", async () => {
    api.fetchFiscalConnections.mockResolvedValue(overview({ mydata }));
    api.saveFiscalConnection.mockResolvedValue({ connection: mydata, check: { result: "ok", error_code: null, detail: {} } });
    wrap();

    const panel = await openPanel("mydata");
    expect(within(panel).queryByTestId("fiscal-connection-env-test")).toBeNull();
    fireEvent.click(within(panel).getByTestId("fiscal-connection-advanced"));
    expect(within(panel).getByTestId("fiscal-connection-env-test")).toHaveTextContent(en.FiscalConnections.environment.testAade);
    fireEvent.click(within(panel).getByTestId("fiscal-connection-env-test"));
    fireEvent.click(within(panel).getByTestId("fiscal-connection-save"));
    await waitFor(() => expect(api.saveFiscalConnection).toHaveBeenCalled());
    expect(api.saveFiscalConnection.mock.calls[0][2]).toMatchObject({ environment: "test" });
  });
});

describe("connections-model", () => {
  it("maps «Test» to the sandbox until credentials exist, and the registry always to its sandbox", () => {
    expect(apiEnvironment("mydata", { environment: "test" }, null)).toBe("sandbox");
    expect(apiEnvironment("mydata", { environment: "test", user_id: "box" }, null)).toBe("test");
    expect(apiEnvironment("tse", { environment: "test", api_key: "k" }, null)).toBe("test");
    expect(apiEnvironment("registry", { environment: "test", username: "u", password: "p" }, null)).toBe("sandbox");
    expect(apiEnvironment("peppol", { environment: "production" }, null)).toBe("production");
  });

  it("never sends an empty secret, so saved ones are kept", () => {
    const till = { device: "tse", environment: "production", has_api_key: true, has_api_secret: true, status: "active" };
    const draft = draftOf("tse", till as never);
    expect(saveBody("tse", draft, till as never)).toEqual({ environment: "production" });
    expect(saveBody("tse", draft, till as never, true)).toEqual({ environment: "production", reprovision: true });
    expect(saveBody("peppol", { environment: "production", legal_entity_id: " sys-1 " }, null)).toEqual({
      environment: "production",
      legal_entity_id: "sys-1",
      peppol_id: null,
    });
  });
});
