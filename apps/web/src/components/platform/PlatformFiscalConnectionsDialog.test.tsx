import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

// ADR-273: the vendor console fills a box's fiscal connections.

const api = vi.hoisted(() => ({
  fetchPlatformFiscalConnections: vi.fn(),
  setPlatformConnectionsManager: vi.fn(),
  savePlatformFiscalConnection: vi.fn(),
  checkPlatformFiscalConnection: vi.fn(),
}));

vi.mock("@/api/fiscal", async (original) => ({ ...(await original<object>()), ...api }));

import { PlatformFiscalConnectionsDialog } from "./PlatformFiscalConnectionsDialog";

const overview = (managedBy: "owner" | "palee") => ({
  country: "BE",
  kinds: ["peppol"],
  managed_by: managedBy,
  connections: { peppol: null },
});

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Brussels">
        <PlatformFiscalConnectionsDialog token="vendor" organizationId="org-1" organizationName="Box Bruxelles" onClose={() => undefined} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("PlatformFiscalConnectionsDialog", () => {
  beforeEach(() => {
    Object.values(api).forEach((mock) => mock.mockReset());
  });

  it("chooses who manages the connections and fills one in for the box", async () => {
    api.fetchPlatformFiscalConnections.mockResolvedValue(overview("owner"));
    api.setPlatformConnectionsManager.mockResolvedValue(overview("palee"));
    api.savePlatformFiscalConnection.mockResolvedValue({
      connection: {
        network: "peppol",
        provider: "fiskaly",
        environment: "production",
        peppol_id: "0208:0403170701",
        legal_entity_id: "sys-1",
        has_api_key: true,
        has_api_secret: true,
        credentials_source: "own",
        has_webhook_token: true,
        status: "active",
        updated_by_platform: true,
      },
      check: { result: "ok", error_code: null, detail: {} },
    });
    wrap();

    const dialog = await screen.findByTestId("platform-fiscal-connections");
    expect(await within(dialog).findByTestId("platform-fiscal-manager-owner")).toHaveAttribute("aria-checked", "true");
    fireEvent.click(within(dialog).getByTestId("platform-fiscal-manager-palee"));
    await waitFor(() => expect(api.setPlatformConnectionsManager).toHaveBeenCalledWith("vendor", "org-1", "palee"));
    await waitFor(() => expect(within(dialog).getByTestId("platform-fiscal-manager-palee")).toHaveAttribute("aria-checked", "true"));

    fireEvent.click(within(dialog).getByTestId("fiscal-connection-peppol"));
    const panel = await screen.findByTestId("fiscal-connection-panel-peppol");
    fireEvent.change(within(panel).getByTestId("fiscal-connection-legal_entity_id"), { target: { value: "sys-1" } });
    fireEvent.change(within(panel).getByTestId("fiscal-connection-api_key"), { target: { value: "key" } });
    fireEvent.change(within(panel).getByTestId("fiscal-connection-api_secret"), { target: { value: "secret" } });
    fireEvent.click(within(panel).getByTestId("fiscal-connection-save"));

    await waitFor(() => expect(api.savePlatformFiscalConnection).toHaveBeenCalled());
    expect(api.savePlatformFiscalConnection.mock.calls[0].slice(0, 3)).toEqual(["vendor", "org-1", "peppol"]);
    expect(api.savePlatformFiscalConnection.mock.calls[0][3]).toMatchObject({ legal_entity_id: "sys-1", api_key: "key", api_secret: "secret" });
    expect(await within(panel).findByTestId("fiscal-connection-saved")).toHaveTextContent(en.FiscalConnections.saved);
  });
});
