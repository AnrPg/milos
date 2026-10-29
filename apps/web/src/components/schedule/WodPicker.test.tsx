import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { WodPicker } from "./WodPicker";

const searchWorkoutChoices = vi.fn();
const fetchSuggestedWorkoutChoices = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, string>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
  useLocale: () => "en",
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/api/workout-choices", () => ({
  searchWorkoutChoices: (...args: unknown[]) => searchWorkoutChoices(...args),
  fetchSuggestedWorkoutChoices: (...args: unknown[]) => fetchSuggestedWorkoutChoices(...args),
}));
vi.mock("@/api/workouts", () => ({
  fetchAdminWorkout: vi.fn(async (_token: string, id: string) => ({ id, title: `Workout ${id}`, type: "strength" })),
  listWorkoutFolders: vi.fn(async () => [{ id: "f1", name: "Benchmarks", parent_id: null }]),
}));

const choice = (id: string, title: string, type = "crossfit") => ({ id, title, type, icon: null });

function renderPicker(props: Partial<Parameters<typeof WodPicker>[0]> = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  const onChange = vi.fn();
  const onCreateNew = vi.fn();
  render(
    <WodPicker
      label="WOD"
      token="tok"
      value={null}
      onChange={onChange}
      onCreateNew={onCreateNew}
      date="2026-10-23"
      classTypeId="ct"
      classTypeName="CrossFit"
      {...props}
    />,
    { wrapper },
  );
  return { onChange, onCreateNew };
}

describe("WodPicker", () => {
  beforeEach(() => {
    searchWorkoutChoices.mockReset();
    fetchSuggestedWorkoutChoices.mockReset();
    fetchSuggestedWorkoutChoices.mockResolvedValue({
      date: "2026-10-23",
      same_day: [choice("w1", "Murph")],
      recent: [choice("w2", "Fran")],
      newest: [choice("w3", "Cindy")],
    });
  });

  it("as calls to action, opens the library or the editor from two plain buttons", async () => {
    const { onCreateNew } = renderPicker({ variant: "actions" });
    expect(screen.getByRole("group", { name: "WOD" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "+ wodPickerNew" }));
    expect(onCreateNew).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole("button", { name: "wodPickerChoose" }));
    expect(await screen.findByRole("dialog")).toBeInTheDocument();
    // The day's WOD stays one tap away.
    expect(await screen.findAllByRole("button", { name: "wodPickerUse:Murph" })).not.toHaveLength(0);
  });

  it("offers the day's WOD as one tap under an empty field", async () => {
    const { onChange } = renderPicker();
    fireEvent.click(await screen.findByRole("button", { name: "wodPickerUse:Murph" }));
    expect(onChange).toHaveBeenCalledWith("w1");
    expect(fetchSuggestedWorkoutChoices).toHaveBeenCalledWith("tok", { date: "2026-10-23", classTypeId: "ct" });
  });

  it("opens on suggestions, then searches the library on the server, page by page", async () => {
    searchWorkoutChoices
      .mockResolvedValueOnce({ workouts: [choice("w9", "Back squat", "strength")], has_more: true, next_offset: 1 })
      .mockResolvedValueOnce({ workouts: [choice("w10", "Front squat", "strength")], has_more: false, next_offset: null });
    const { onChange } = renderPicker();

    fireEvent.click(screen.getByRole("button", { name: /WOD wodPickerNone/ }));
    expect(await screen.findByText("wodPickerSameDay:Fri, Oct 23")).toBeInTheDocument();
    expect(screen.getByText("wodPickerRecent:CrossFit")).toBeInTheDocument();
    expect(screen.getAllByRole("option").map((option) => option.textContent)).toEqual([
      "○wodPickerNonewodPickerNoneHint✓",
      expect.stringContaining("Murph"),
      expect.stringContaining("Fran"),
      expect.stringContaining("Cindy"),
    ]);
    expect(searchWorkoutChoices).not.toHaveBeenCalled();

    fireEvent.change(screen.getByRole("searchbox", { name: "wodPickerSearch" }), { target: { value: "squat" } });
    expect(await screen.findByText("Back squat")).toBeInTheDocument();
    expect(searchWorkoutChoices).toHaveBeenCalledWith("tok", { q: "squat", type: "", folderId: "", offset: 0 });

    fireEvent.click(screen.getByRole("button", { name: "wodPickerShowMore" }));
    expect(await screen.findByText("Front squat")).toBeInTheDocument();
    expect(searchWorkoutChoices).toHaveBeenLastCalledWith("tok", { q: "squat", type: "", folderId: "", offset: 1 });

    fireEvent.keyDown(screen.getByRole("searchbox"), { key: "ArrowDown" });
    fireEvent.keyDown(screen.getByRole("searchbox"), { key: "Enter" });
    expect(onChange).toHaveBeenCalledWith("w10");
  });

  it("offers a new WOD when the search finds nothing", async () => {
    searchWorkoutChoices.mockResolvedValue({ workouts: [], has_more: false, next_offset: null });
    const { onCreateNew } = renderPicker();
    fireEvent.click(screen.getByRole("button", { name: /WOD wodPickerNone/ }));
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "zzz" } });
    expect(await screen.findByText("wodPickerNoMatch:zzz")).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole("button", { name: "+ wodPickerNew" }).at(-1)!);
    expect(onCreateNew).toHaveBeenCalled();
  });

  it("shows the chosen WOD by name and clears it", async () => {
    const { onChange } = renderPicker({ value: "w5" });
    expect(await screen.findByText("Workout w5")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /wodPickerUse/ })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "wodPickerClear" }));
    await waitFor(() => expect(onChange).toHaveBeenCalledWith(null));
  });
});
