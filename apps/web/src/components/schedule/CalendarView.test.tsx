import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import type { ScheduleSlot } from "@/api/schedule";

import { CalendarView } from "./CalendarView";

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, string>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

function slot(id: string, scheduledAt: string, name = "CrossFit"): ScheduleSlot {
  return {
    id,
    scheduled_at: scheduledAt,
    duration_minutes: 60,
    class_type_id: "ct",
    class_type: { id: "ct", name, slug: "crossfit" },
    capacity: 12,
    approved_booking_count: 0,
    spots_remaining: 12,
    workout: null,
    bookings: [],
  } as unknown as ScheduleSlot;
}

// Five classes on the 14th: the month cell shows three and "+2 more".
const busyDay = ["06", "08", "10", "17", "19"].map((hour, index) => slot(`s${index}`, `2026-10-14T${hour}:00:00Z`));
const otherDay = slot("other", "2026-10-15T09:00:00Z", "Yoga");

const base = {
  isAdmin: false,
  onCreateSlot: () => undefined,
  onSelectSlot: () => undefined,
  timeZone: "UTC",
};

describe("CalendarView", () => {
  it("in the month view, a date or its '+N more' opens that day", () => {
    const onOpenDay = vi.fn();
    render(<CalendarView {...base} days={30} startDate="2026-10-01" slots={[...busyDay, otherDay]} onOpenDay={onOpenDay} />);

    const dayButtons = screen.getAllByRole("button", { name: /^openDayView:Wednesday, Oct 14$/ });
    // The date number and "+2 more" both lead to the day.
    expect(dayButtons).toHaveLength(2);
    expect(dayButtons[1]).toHaveTextContent("+2 moree7c95b4");

    fireEvent.click(dayButtons[0]);
    fireEvent.click(dayButtons[1]);
    expect(onOpenDay).toHaveBeenNthCalledWith(1, "2026-10-14");
    expect(onOpenDay).toHaveBeenNthCalledWith(2, "2026-10-14");

    fireEvent.click(screen.getByRole("button", { name: "openDayView:Thursday, Oct 15" }));
    expect(onOpenDay).toHaveBeenLastCalledWith("2026-10-15");
  });

  it("the day view lists every class of that day and nothing else", () => {
    render(<CalendarView {...base} days={1} startDate="2026-10-14" slots={[...busyDay, otherDay]} />);

    const day = screen.getByRole("heading", { name: "Wednesday, Oct 14" }).closest("section")!;
    expect(within(day).getAllByText("CrossFit")).toHaveLength(5);
    expect(screen.queryByText("Yoga")).not.toBeInTheDocument();
  });
});
