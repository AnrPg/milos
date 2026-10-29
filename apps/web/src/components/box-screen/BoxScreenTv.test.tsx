import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import { ApiError } from "@/api/client";
import type { BoxScreenToday } from "@/api/box-screens";

import { BoxScreenTv, ScreenDay } from "./BoxScreenTv";

const pairBoxScreen = vi.fn();

vi.mock("@/api/box-screens", async (original) => ({
  ...(await original<typeof import("@/api/box-screens")>()),
  pairBoxScreen: (code: string) => pairBoxScreen(code),
}));
vi.mock("./useBoxScreen", () => ({
  useBoxScreenTimer: () => ({ payload: null, position: null }),
  useBoxScreenToday: () => ({ today: null, error: null, token: "display", now: Date.now() }),
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

const T = (time: string) => `2026-10-29T${time}:00Z`;
const at = (time: string) => Date.parse(T(time));

function wrap(ui: ReactNode) {
  return (
    <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
      {ui}
    </NextIntlClientProvider>
  );
}

function day(focus: Partial<BoxScreenToday["focus"]> = {}, entries = [{ name: "Eleni", rank: 1, value: "3:42", unit: null, scale_level_slug: "rx" }]): BoxScreenToday {
  return {
    box: { id: "org-1", name: "Box Kypseli" },
    screen: { id: "s1", name: "Room 1", branch: null },
    date: "2026-10-29",
    time_zone: "UTC",
    server_now: T("17:52"),
    classes: [
      {
        id: "c18",
        name: "CrossFit",
        class_type: "CrossFit",
        coach_name: "Nikos",
        scheduled_at: T("18:00"),
        ends_at: T("19:00"),
        duration_minutes: 60,
        cancelled: false,
        location_id: null,
        workout_id: "fran",
        bookings: { names: ["Maria", "Eleni", "Nikos"], count: 5, capacity: 14, unnamed: 2, waitlist: 0 },
      },
    ],
    workouts: [{ id: "fran", title: "Fran", type: "for_time", body: { kind: "free_text", text: "21-15-9 Thrusters, Pull-ups", document: null, timer: null, structured: false } }],
    leaderboards: [{ workout_id: "fran", score: null, entries }],
    focus: { view: "preview", source: "auto", slot_id: "c18", until: null, ...focus },
  };
}

describe("the box screen on the TV", () => {
  beforeEach(() => {
    pairBoxScreen.mockReset();
    window.localStorage.clear();
  });

  it("pairs with the code staff read out, whatever its case and dashes", async () => {
    pairBoxScreen.mockResolvedValue({ token: "display", expires_at: T("18:00"), screen: { id: "s1", name: "Room 1" }, box: { id: "org-1", name: "Box" } });
    render(wrap(<BoxScreenTv />));

    const input = await screen.findByTestId("tv-code");
    fireEvent.change(input, { target: { value: "acef 346" } });
    expect(input).toHaveValue("ACEF-346");
    expect(screen.getByTestId("tv-pair")).toBeDisabled();

    fireEvent.change(input, { target: { value: "acef-3467" } });
    fireEvent.click(screen.getByTestId("tv-pair"));

    await waitFor(() => expect(pairBoxScreen).toHaveBeenCalledWith("ACEF3467"));
    await waitFor(() => expect(JSON.parse(window.localStorage.getItem("palee:box-screen") ?? "{}").token).toBe("display"));
  });

  it("explains a wrong or expired code under the field", async () => {
    pairBoxScreen.mockRejectedValue(new ApiError(422, "Wrong", { code: "invalid_pairing_code" }));
    render(wrap(<BoxScreenTv />));

    fireEvent.change(await screen.findByTestId("tv-code"), { target: { value: "AAAAAAAA" } });
    fireEvent.click(screen.getByTestId("tv-pair"));

    expect(await screen.findByRole("alert")).toHaveTextContent(en.BoxScreens.tvCodeInvalid);
    expect(screen.getByTestId("tv-code")).toHaveAttribute("aria-invalid", "true");
  });

  it("before the class: the WOD and who is booked, by first name only", () => {
    render(wrap(<ScreenDay today={day()} token="display" now={at("17:52")} />));

    expect(screen.getByTestId("tv-screen")).toHaveAttribute("data-scene", "preview");
    expect(screen.getByTestId("tv-bar-sub")).toHaveTextContent("In 8′: 06:00 PM CrossFit");
    expect(screen.getByTestId("tv-wod")).toHaveTextContent("Fran");
    expect(screen.getByTestId("tv-wod")).toHaveTextContent("21-15-9 Thrusters, Pull-ups");
    const bookings = screen.getByTestId("tv-bookings");
    expect(bookings).toHaveTextContent("06:00 PM CrossFit · 5/14");
    expect(bookings).toHaveTextContent("Maria");
    expect(bookings).toHaveTextContent("+2");
    expect(bookings).toHaveTextContent("9 spots left · book in the app");
  });

  it("during the class: the timer and who has finished", () => {
    render(wrap(<ScreenDay today={day({ view: "timer" })} token="display" now={at("18:07")} />));

    expect(screen.getByTestId("tv-screen")).toHaveAttribute("data-scene", "timer");
    expect(screen.getByRole("timer")).toHaveTextContent("07:00");
    expect(screen.getByTestId("tv-finished")).toHaveTextContent("Eleni 3:42");
  });

  it("after the class: the leaderboard, marking a score that just came in", () => {
    const { rerender } = render(wrap(<ScreenDay today={day({ view: "results" })} token="display" now={at("19:10")} />));
    const board = screen.getByTestId("tv-leaderboard");
    expect(board).toHaveTextContent("Leaderboard · Fran");
    expect(board).toHaveTextContent("Eleni");
    expect(board).toHaveTextContent("Rx");
    expect(board.querySelector("[data-new]")).toBeNull();

    act(() => {
      rerender(
        wrap(
          <ScreenDay
            today={day({ view: "results" }, [
              { name: "Eleni", rank: 1, value: "3:42", unit: null, scale_level_slug: "rx" },
              { name: "Maria", rank: 2, value: "3:58", unit: null, scale_level_slug: "rx" },
            ])}
            token="display"
            now={at("19:11")}
          />,
        ),
      );
    });
    const fresh = screen.getByTestId("tv-leaderboard").querySelector("[data-new]");
    expect(fresh).toHaveTextContent("Maria");
    expect(fresh).toHaveTextContent(en.BoxScreens.tvNew);
  });

  it("shows what staff pinned, and says when the day is over", () => {
    const { rerender } = render(wrap(<ScreenDay today={day({ view: "leaderboard", source: "staff" })} token="display" now={at("12:00")} />));
    expect(screen.getByTestId("tv-screen")).toHaveAttribute("data-scene", "leaderboard");
    expect(screen.getByTestId("tv-bar-sub")).toHaveTextContent("06:00 PM CrossFit · Leaderboard");

    rerender(wrap(<ScreenDay today={day({ view: "wod", source: "staff" })} token="display" now={at("12:00")} />));
    expect(screen.getByTestId("tv-wod")).toHaveTextContent("Fran");

    rerender(wrap(<ScreenDay today={day({ view: "idle", slot_id: null })} token="display" now={at("21:00")} />));
    expect(screen.getByTestId("tv-idle")).toHaveTextContent(en.BoxScreens.tvDayDone);
  });
});
