import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { formatDurationInput, parseDurationInput, TimeInput } from "./TimeInput";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

describe("parseDurationInput", () => {
  it.each([
    ["90", 90],
    ["1:30", 90],
    ["12:00", 720],
    ["1:00:00", 3600],
    ["90s", 90],
    ["12m", 720],
    ["1m30s", 90],
    ["1 min 30 sec", 90],
    ["1h", 3600],
  ])("reads %s as %i seconds", (text, seconds) => {
    expect(parseDurationInput(text)).toBe(seconds);
  });

  it("treats an empty field as unset and rejects nonsense", () => {
    expect(parseDurationInput("  ")).toBeNull();
    expect(parseDurationInput("1:75")).toBe("invalid");
    expect(parseDurationInput("abc")).toBe("invalid");
  });

  it("formats seconds as m:ss", () => {
    expect(formatDurationInput(90)).toBe("1:30");
    expect(formatDurationInput(3725)).toBe("1:02:05");
    expect(formatDurationInput(null)).toBe("");
  });
});

describe("TimeInput", () => {
  it("accepts more than 59 seconds and applies presets", () => {
    const onChange = vi.fn();
    render(<TimeInput value={null} onChange={onChange} presets={[20, 600]} ariaLabel="Rest" />);

    fireEvent.change(screen.getByRole("textbox", { name: "Rest" }), { target: { value: "90" } });
    expect(onChange).toHaveBeenLastCalledWith(90);

    fireEvent.click(screen.getByRole("button", { name: "10:00" }));
    expect(onChange).toHaveBeenLastCalledWith(600);
  });
});
