import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ fetchGuestBoxes: vi.fn() }));
vi.mock("@/api/desk-collect", async (original) => ({ ...(await original<object>()), ...api }));

import { GuestBanner } from "./GuestBanner";

const BOX = { organization_id: "org-1", slug: "kypseli", name: "Box Κυψέλη" };

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <GuestBanner token="token" box={BOX} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

// ADR-272: a guest of the box sees it, with «Γίνε μέλος box».
describe("GuestBanner", () => {
  beforeEach(() => api.fetchGuestBoxes.mockReset());

  it("tells a guest of this box and links to its packages", async () => {
    api.fetchGuestBoxes.mockResolvedValue({ boxes: [{ id: "org-1", name: "Box Κυψέλη", slug: "kypseli" }] });
    wrap();
    expect(await screen.findByText("Είσαι επισκέπτης του Box Κυψέλη")).toBeTruthy();
    expect(screen.getByTestId("box-guest-join").getAttribute("href")).toBe("/b/kypseli/packages");
    expect(screen.getByTestId("box-guest-join").textContent).toBe("Γίνε μέλος box");
  });

  it("shows nothing to someone who is not a guest here", async () => {
    api.fetchGuestBoxes.mockResolvedValue({ boxes: [{ id: "org-2", name: "Άλλο box", slug: "allo" }] });
    wrap();
    await vi.waitFor(() => expect(api.fetchGuestBoxes).toHaveBeenCalled());
    expect(screen.queryByTestId("box-guest-banner")).toBeNull();
  });
});
