import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useLocale: () => "en-GB",
}));

import { DateInput, TimeInput } from "./DateInput";

describe("ui/DateInput", () => {
  it("shows the date in the viewer's language and picks a day from the calendar", () => {
    const onValueChange = vi.fn();
    render(<DateInput aria-label="Starts" value="2026-10-22" onValueChange={onValueChange} />);
    const trigger = screen.getByRole("button", { name: "Starts" });
    expect(trigger).toHaveTextContent("22 Oct 2026");

    fireEvent.click(trigger);
    expect(screen.getByRole("dialog", { name: "chooseDate" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /24 October 2026/ }));
    expect(onValueChange).toHaveBeenCalledWith("2026-10-24");
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("disables days outside min and max and clears an optional value", () => {
    const onValueChange = vi.fn();
    render(<DateInput aria-label="Ends" value="2026-10-22" min="2026-10-20" max="2026-10-25" onValueChange={onValueChange} />);
    fireEvent.click(screen.getByRole("button", { name: "Ends" }));
    expect(screen.getByRole("button", { name: /19 October 2026/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: /26 October 2026/ })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "clear" }));
    expect(onValueChange).toHaveBeenCalledWith("");
  });

  it("jumps through months and years for far-away dates", () => {
    const onValueChange = vi.fn();
    render(<DateInput aria-label="Born" value="2026-10-22" onValueChange={onValueChange} />);
    fireEvent.click(screen.getByRole("button", { name: "Born" }));
    fireEvent.click(screen.getByRole("button", { name: "chooseMonthYear" }));
    fireEvent.click(screen.getByRole("button", { name: "chooseMonthYear" }));
    for (let page = 0; page < 3; page += 1) fireEvent.click(screen.getByRole("button", { name: "previousYears" }));
    fireEvent.click(screen.getByRole("button", { name: "1990" }));
    fireEvent.click(screen.getByRole("button", { name: "Mar" }));
    fireEvent.click(screen.getByRole("button", { name: /15 March 1990/ }));
    expect(onValueChange).toHaveBeenCalledWith("1990-03-15");
  });
});

describe("ui/TimeInput", () => {
  it("picks hours and minutes in 24-hour columns", () => {
    const onValueChange = vi.fn();
    render(<TimeInput aria-label="From" value="18:30" onValueChange={onValueChange} />);
    fireEvent.click(screen.getByRole("button", { name: "From" }));
    fireEvent.click(screen.getByRole("option", { name: "07" }));
    expect(onValueChange).toHaveBeenCalledWith("07:30");
  });
});
