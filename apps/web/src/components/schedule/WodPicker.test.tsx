import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import type { WorkoutRecord } from "@/api/workouts";

import { WodPicker, filterWorkouts } from "./WodPicker";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, string>) => (values?.query ? `${key}:${values.query}` : key),
  useLocale: () => "en",
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

const workout = (id: string, title: string, type: string, updated_at: string) =>
  ({ id, title, type, updated_at, available_scale_levels: [], sections: [] }) as unknown as WorkoutRecord;

const library = [
  workout("w1", "Fran", "for_time", "2026-10-01T10:00:00Z"),
  workout("w2", "Ταμπάτα Murph", "amrap", "2026-10-20T10:00:00Z"),
  workout("w3", "Back squat 5x5", "strength", "2026-10-10T10:00:00Z"),
];

describe("filterWorkouts", () => {
  it("lists the newest first and finds words without accents or case", () => {
    expect(filterWorkouts(library, "", (type) => type).map((w) => w.id)).toEqual(["w2", "w3", "w1"]);
    expect(filterWorkouts(library, "ταμπατα", (type) => type).map((w) => w.id)).toEqual(["w2"]);
    expect(filterWorkouts(library, "squat strength", (type) => type).map((w) => w.id)).toEqual(["w3"]);
  });
});

describe("WodPicker", () => {
  it("searches, picks with the keyboard and offers a new WOD when nothing matches", () => {
    const onChange = vi.fn();
    const onCreateNew = vi.fn();
    render(<WodPicker label="WOD" workouts={library} value={null} onChange={onChange} onCreateNew={onCreateNew} />);

    fireEvent.click(screen.getByRole("button", { name: /WOD wodPickerNone/ }));
    const search = screen.getByRole("combobox", { name: "wodPickerSearch" });
    expect(screen.getAllByRole("option")).toHaveLength(4);

    fireEvent.change(search, { target: { value: "fran" } });
    expect(screen.getAllByRole("option")).toHaveLength(1);
    fireEvent.keyDown(search, { key: "Enter" });
    expect(onChange).toHaveBeenCalledWith("w1");

    fireEvent.click(screen.getByRole("button", { name: /WOD wodPickerNone/ }));
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "zzz" } });
    expect(screen.getByText("wodPickerNoMatch:zzz")).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole("button", { name: "+ wodPickerNew" }).at(-1)!);
    expect(onCreateNew).toHaveBeenCalled();
  });

  it("shows the chosen WOD and clears it", () => {
    const onChange = vi.fn();
    render(<WodPicker label="WOD" workouts={library} value="w3" onChange={onChange} onCreateNew={() => undefined} />);
    expect(screen.getByText("Back squat 5x5")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "wodPickerClear" }));
    expect(onChange).toHaveBeenCalledWith(null);
  });
});
