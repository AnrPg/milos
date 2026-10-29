import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { BoxScreen } from "@/api/box-screens";

import { BoxScreensSettings } from "./BoxScreensSettings";

const api = {
  listBoxScreens: vi.fn(),
  createBoxScreen: vi.fn(),
  updateBoxScreen: vi.fn(),
  deleteBoxScreen: vi.fn(),
  newBoxScreenPairingCode: vi.fn(),
  pinBoxScreen: vi.fn(),
  unpinBoxScreen: vi.fn(),
};

vi.mock("@/api/box-screens", async (original) => ({
  ...(await original<typeof import("@/api/box-screens")>()),
  listBoxScreens: (...args: unknown[]) => api.listBoxScreens(...args),
  createBoxScreen: (...args: unknown[]) => api.createBoxScreen(...args),
  updateBoxScreen: (...args: unknown[]) => api.updateBoxScreen(...args),
  deleteBoxScreen: (...args: unknown[]) => api.deleteBoxScreen(...args),
  newBoxScreenPairingCode: (...args: unknown[]) => api.newBoxScreenPairingCode(...args),
  pinBoxScreen: (...args: unknown[]) => api.pinBoxScreen(...args),
  unpinBoxScreen: (...args: unknown[]) => api.unpinBoxScreen(...args),
}));
vi.mock("@/api/facility", () => ({
  listAdminLocations: async () => [{ id: "kyp", name: "Kypseli", address: null, archived_at: null }],
}));
vi.mock("@/api/schedule", () => ({
  fetchSchedule: async () => ({ slots: [{ id: "c18", name: "CrossFit", scheduled_at: "2026-10-29T18:00:00Z", location_id: "kyp", cancelled_at: null }] }),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "staff" } }) }));
vi.mock("@/lib/organization-slug", () => ({
  adminHref: (href: string) => href,
  useOrganizationSlug: () => "box1",
  useOrganizationTimeZone: () => "UTC",
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

function screenRow(extra: Partial<BoxScreen> = {}): BoxScreen {
  return {
    id: "s1",
    name: "Room 1",
    location_id: "kyp",
    paired: true,
    paired_at: "2026-10-29T08:00:00Z",
    pairing_expires_at: null,
    last_seen_at: null,
    inserted_at: "2026-10-28T08:00:00Z",
    override: null,
    focus_changed: null,
    ...extra,
  };
}

function wrap(ui: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const list = (screens: BoxScreen[]) => ({ screens, max_screens: 20, override_views: ["wod", "timer", "leaderboard", "bookings", "class"] });

describe("Settings › Box screens", () => {
  beforeEach(() => Object.values(api).forEach((fn) => fn.mockReset()));

  it("lists each screen with its branch, whether it is connected and what it shows", async () => {
    api.listBoxScreens.mockResolvedValue(
      list([
        screenRow(),
        screenRow({
          id: "s2",
          name: "Room 2",
          location_id: null,
          paired: false,
          paired_at: null,
          pairing_expires_at: "2999-01-01T00:00:00Z",
          override: { view: "leaderboard", slot_id: null, until: "2026-10-29T19:30:00Z" },
          focus_changed: { at: "2026-10-29T17:00:00Z", by: { id: "u1", name: "Olga" } },
        }),
      ]),
    );
    wrap(<BoxScreensSettings />);

    const first = await screen.findByTestId("box-screen-s1");
    expect(first).toHaveTextContent("Kypseli · follows the branch's classes");
    expect(first).toHaveTextContent(en.BoxScreens.paired);
    expect(within(first).getByTestId("box-screen-focus")).toHaveTextContent("Shows: Automatic");
    expect(within(first).queryByTestId("box-screen-auto")).toBeNull();

    const second = screen.getByTestId("box-screen-s2");
    expect(second).toHaveTextContent("Whole box · follows every class");
    expect(second).toHaveTextContent(en.BoxScreens.waiting);
    expect(within(second).getByTestId("box-screen-focus")).toHaveTextContent("Pinned: Leaderboard · until 07:30 PM");
    expect(within(second).getByTestId("box-screen-focus")).toHaveTextContent("Changed by Olga");
  });

  it("pins a view until a time and returns it to automatic", async () => {
    api.listBoxScreens.mockResolvedValue(list([screenRow({ override: { view: "wod", slot_id: null, until: null } })]));
    api.pinBoxScreen.mockResolvedValue({ screen: screenRow() });
    api.unpinBoxScreen.mockResolvedValue({ screen: screenRow() });
    wrap(<BoxScreensSettings />);

    fireEvent.click(await screen.findByTestId("box-screen-auto"));
    await waitFor(() => expect(api.unpinBoxScreen).toHaveBeenCalledWith("staff", "s1"));

    fireEvent.click(screen.getByTestId("box-screen-choose"));
    const dialog = await screen.findByTestId("box-screen-choose-dialog");
    fireEvent.click(within(dialog).getByTestId("box-screen-view-class"));
    expect(within(dialog).getByTestId("box-screen-pin")).toBeDisabled();
    expect(await within(dialog).findByTestId("box-screen-class")).toBeInTheDocument();

    fireEvent.click(within(dialog).getByTestId("box-screen-view-bookings"));
    fireEvent.click(within(dialog).getByTestId("box-screen-pin"));
    await waitFor(() => expect(api.pinBoxScreen).toHaveBeenCalledWith("staff", "s1", { view: "bookings", slot_id: null, until: null }));
  });

  it("adds a screen for a branch and shows its pairing code", async () => {
    api.listBoxScreens.mockResolvedValue(list([]));
    api.createBoxScreen.mockResolvedValue({
      screen: screenRow({ paired: false, paired_at: null }),
      pairing_code: { code: "ACEF-3467", expires_at: "2999-01-01T00:00:00Z" },
    });
    wrap(<BoxScreensSettings />);

    fireEvent.click(await screen.findByTestId("box-screen-add"));
    const dialog = await screen.findByTestId("box-screen-add-dialog");
    fireEvent.change(within(dialog).getByTestId("box-screen-name"), { target: { value: "Room 1" } });
    fireEvent.click(within(dialog).getByTestId("box-screen-create"));

    await waitFor(() => expect(api.createBoxScreen).toHaveBeenCalledWith("staff", { name: "Room 1", location_id: "kyp" }));
    expect(await screen.findByTestId("box-screen-code")).toHaveTextContent("ACEF-3467");
  });

  it("explains a refused name under the field", async () => {
    const { ApiError } = await import("@/api/client");
    api.listBoxScreens.mockResolvedValue(list([]));
    api.createBoxScreen.mockRejectedValue(new ApiError(422, "Name", { code: "invalid_screen_name" }));
    wrap(<BoxScreensSettings />);

    fireEvent.click(await screen.findByTestId("box-screen-add"));
    const dialog = await screen.findByTestId("box-screen-add-dialog");
    fireEvent.change(within(dialog).getByTestId("box-screen-name"), { target: { value: "x" } });
    fireEvent.click(within(dialog).getByTestId("box-screen-create"));

    expect(await within(dialog).findByText(en.BoxScreens.errorName)).toBeInTheDocument();
    expect(within(dialog).getByTestId("box-screen-name")).toHaveAttribute("aria-invalid", "true");
  });
});
