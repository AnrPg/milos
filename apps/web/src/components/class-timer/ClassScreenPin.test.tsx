import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import { ApiError } from "@/api/client";
import type { BoxScreen } from "@/api/box-screens";

import { ClassScreenPin } from "./ClassScreenPin";

const api = { listClassScreens: vi.fn(), pinClassScreen: vi.fn(), unpinClassScreen: vi.fn() };

vi.mock("@/api/box-screens", async (original) => ({
  ...(await original<typeof import("@/api/box-screens")>()),
  listClassScreens: (...args: unknown[]) => api.listClassScreens(...args),
  pinClassScreen: (...args: unknown[]) => api.pinClassScreen(...args),
  unpinClassScreen: (...args: unknown[]) => api.unpinClassScreen(...args),
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

const coachViews = ["timer", "leaderboard", "wod"];

describe("«On screen» on the class timer remote", () => {
  beforeEach(() => Object.values(api).forEach((fn) => fn.mockReset()));

  it("is hidden when no screen can show the class, or the person may not change any", async () => {
    api.listClassScreens.mockResolvedValueOnce({ screens: [], views: coachViews });
    const { unmount } = wrap(<ClassScreenPin token="coach" slotId="c18" />);
    await waitFor(() => expect(api.listClassScreens).toHaveBeenCalledWith("coach", "c18"));
    expect(screen.queryByTestId("class-screen-open")).toBeNull();
    unmount();

    api.listClassScreens.mockRejectedValueOnce(new ApiError(403, "Forbidden", { code: "forbidden", error: "Forbidden" }));
    wrap(<ClassScreenPin token="other-coach" slotId="c18" />);
    await waitFor(() => expect(api.listClassScreens).toHaveBeenCalledTimes(2));
    expect(screen.queryByTestId("class-screen-open")).toBeNull();
  });

  it("pins the class's timer, leaderboard or WOD and returns the screen to automatic", async () => {
    api.listClassScreens.mockResolvedValue({ screens: [screenRow()], views: coachViews });
    api.pinClassScreen.mockResolvedValue({ screen: screenRow({ override: { view: "leaderboard", slot_id: "c18", until: null } }) });
    wrap(<ClassScreenPin token="coach" slotId="c18" />);

    fireEvent.click(await screen.findByRole("button", { name: "On screen" }));
    const dialog = await screen.findByTestId("class-screen-dialog");
    expect(within(dialog).getByText("Show this class on a screen")).toBeTruthy();
    const row = within(dialog).getByTestId("class-screen-s1");
    expect(within(row).getByTestId("class-screen-shows").textContent).toContain("Automatic");
    expect(within(row).getByRole("button", { name: "Class timer" })).toBeTruthy();
    expect(within(row).getByRole("button", { name: "Class WOD" })).toBeTruthy();
    expect(within(row).queryByTestId("class-screen-auto")).toBeNull();

    api.listClassScreens.mockResolvedValue({
      screens: [screenRow({ override: { view: "leaderboard", slot_id: "c18", until: null } })],
      views: coachViews,
    });
    fireEvent.click(within(row).getByRole("button", { name: "Class leaderboard" }));
    await waitFor(() => expect(api.pinClassScreen).toHaveBeenCalledWith("coach", "c18", "s1", { view: "leaderboard" }));

    await waitFor(() => expect(within(dialog).getByTestId("class-screen-shows").textContent).toContain("Pinned: Class leaderboard"));
    expect(within(dialog).getByRole("button", { name: "Class leaderboard" }).getAttribute("aria-pressed")).toBe("true");

    api.unpinClassScreen.mockResolvedValue({ screen: screenRow() });
    api.listClassScreens.mockResolvedValue({ screens: [screenRow()], views: coachViews });
    fireEvent.click(within(dialog).getByRole("button", { name: "Back to automatic" }));
    await waitFor(() => expect(api.unpinClassScreen).toHaveBeenCalledWith("coach", "c18", "s1"));
    await waitFor(() => expect(within(dialog).getByTestId("class-screen-shows").textContent).toContain("Automatic"));
  });

  it("shows another choice without offering to undo it, and keeps a refusal inside the dialog", async () => {
    api.listClassScreens.mockResolvedValue({
      screens: [screenRow({ override: { view: "wod", slot_id: null, until: null } })],
      views: coachViews,
    });
    api.pinClassScreen.mockRejectedValue(new ApiError(403, "Forbidden", { code: "forbidden", error: "Forbidden" }));
    wrap(<ClassScreenPin token="coach" slotId="c18" />);

    fireEvent.click(await screen.findByRole("button", { name: "On screen" }));
    const dialog = await screen.findByTestId("class-screen-dialog");
    expect(within(dialog).getByTestId("class-screen-shows").textContent).toContain("Pinned: Day WOD");
    expect(within(dialog).queryByTestId("class-screen-auto")).toBeNull();

    fireEvent.click(within(dialog).getByRole("button", { name: "Class timer" }));
    await waitFor(() => expect(api.pinClassScreen).toHaveBeenCalled());
    await waitFor(() => expect(within(dialog).getByRole("alert")).toBeTruthy());
  });
});
