import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { PlanSection } from "@/lib/structured-plan/types";

import el from "../../../../../messages/el.json";

import { SAMPLE } from "./fixtures";
import { PlanGrid } from "./index";
import { readPlan, seedPlan } from "./store-adapter";

vi.mock("./useExerciseCatalog", () => ({
  useExerciseCatalog: () => [
    { id: "lib-bs", label: "Back Squat", aliases: [] },
    { id: "lib-dl", label: "Deadlift", aliases: [] },
  ],
}));

const ID = "sec";

function renderGrid(plan: PlanSection) {
  seedPlan(ID, structuredClone(plan));
  return render(
    <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
      <PlanGrid sectionId={ID} />
    </NextIntlClientProvider>,
  );
}

const cell = (row: string, col: number | "same", key: string) => screen.getByTestId(`plan-cell-${row}-${col}-${key}`) as HTMLInputElement;
const type = (input: HTMLElement, value: string) => fireEvent.change(input, { target: { value } });
const hint = () => screen.getByTestId("plan-hint").textContent ?? "";
const plan = () => readPlan(ID)!;

/** A Σετ section with one exercise and nothing typed yet. */
const emptySets = (): PlanSection => ({
  v: 1,
  flow: "sets",
  params: { sets: "4", rest: "2:00" },
  blocks: [[{ id: "a", kind: "ex", name: "Back Squat", dose: "", load: "", cells: [], group: null }]],
  score: "",
  structs: {},
  mods: {},
  interrupt: [],
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("PlanGrid value fields", () => {
  it("shows the computed value inside the field: +5 after 60kg reads 65 with a +5 badge", () => {
    renderGrid(emptySets());
    type(cell("a", 0, "l"), "60kg");
    type(cell("a", 1, "l"), "+5");
    const display = screen.getByTestId("plan-cell-a-1-l-display");
    expect(display).toHaveTextContent("65");
    expect(within(display).getByText("+5")).toBeInTheDocument();
    // the sets after it inherit and keep adding
    expect(cell("a", 2, "l").placeholder).toBe("70");
    expect(cell("a", 3, "l").placeholder).toBe("75");
    // the unit sits once in the row label
    expect(screen.getByText("Φορτίο kg")).toBeInTheDocument();
  });

  it("infers the unit from any set of the row and turns a row with no unit red", () => {
    renderGrid(emptySets());
    type(cell("a", 0, "l"), "60");
    type(cell("a", 1, "l"), "70");
    expect(cell("a", 0, "l")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByTestId("plan-cell-a-0-l-field")).toHaveAttribute("data-bad");
    fireEvent.focus(cell("a", 0, "l"));
    expect(hint()).toContain("Γράψε kg ή % σε ένα σετ της γραμμής");

    type(cell("a", 1, "l"), "70%");
    expect(cell("a", 0, "l")).not.toHaveAttribute("aria-invalid");
    expect(screen.getByText("Φορτίο %")).toBeInTheDocument();
  });

  it("turns a kg / % mix red and says so in the hint line, never under the field", () => {
    renderGrid(emptySets());
    type(cell("a", 0, "l"), "60kg");
    type(cell("a", 1, "l"), "70%");
    expect(cell("a", 1, "l")).toHaveAttribute("aria-invalid", "true");
    fireEvent.focus(cell("a", 1, "l"));
    expect(hint()).toContain("Ίδια μονάδα σε όλη τη γραμμή: kg");
    expect(screen.getByTestId("plan-cell-a-1-l-field").textContent).not.toContain("Ίδια μονάδα");
  });

  it("asks for kg or % on a bare load in a same-every-round row", () => {
    renderGrid(SAMPLE.amrapWindows!);
    type(cell("wbl", "same", "l"), "20");
    expect(cell("wbl", "same", "l")).toHaveAttribute("aria-invalid", "true");
    fireEvent.focus(cell("wbl", "same", "l"));
    expect(hint()).toContain("Γράψε kg ή %, π.χ. 60kg ή 70%");
  });

  it("explains the focused value and gives tips for that kind of field", () => {
    renderGrid(SAMPLE.sets!);
    fireEvent.focus(cell("sq", 1, "l"));
    expect(hint()).toContain("= 65%");
    expect(hint()).toContain("ανεβαίνει κάθε φορά");
    fireEvent.focus(cell("sq", 0, "tempo"));
    expect(hint()).toContain("↓3 κατέβασμα");
  });
});

describe("PlanGrid per round", () => {
  it("summarises a per-round row and grows the AMRAP table as the coach types into the last column", () => {
    renderGrid(SAMPLE.amrapPerRound!);
    expect(screen.getByTestId("plan-sum-ps-d")).toHaveTextContent("5 → 15");
    expect(screen.getByTestId("plan-sum-ps-l")).toHaveTextContent("40 kg → 55 kg");
    // three rounds written plus one empty column
    expect(screen.queryByTestId("plan-cell-ps-3-d")).toBeInTheDocument();
    expect(screen.queryByTestId("plan-cell-ps-4-d")).not.toBeInTheDocument();
    type(cell("ps", 3, "d"), "20");
    expect(screen.getByTestId("plan-cell-ps-4-d")).toBeInTheDocument();
    expect(screen.getByTestId("plan-sum-ps-d")).toHaveTextContent("5 → 20");
    fireEvent.focus(cell("ps", 4, "d"));
    expect(hint()).toContain("μετά τον τελευταίο γύρο");
  });

  it("switches a row to per-round values with Alt+V and back", () => {
    renderGrid(SAMPLE.differentRounds!);
    fireEvent.keyDown(cell("ro", "same", "d"), { key: "v", code: "KeyV", altKey: true });
    expect(plan().blocks[0]![0]!.perRound).toBe(true);
    expect(plan().blocks[0]![0]!.cells[0]).toMatchObject({ d: "500 m" });
    // the round columns of block 1 are rounds 1 and 3
    expect(screen.getByTestId("plan-rounds-ro")).toHaveTextContent("Γύρος 3");
    fireEvent.keyDown(cell("ro", 0, "d"), { key: "v", code: "KeyV", altKey: true });
    expect(plan().blocks[0]![0]!.perRound).toBe(false);
    expect(plan().blocks[0]![0]!.dose).toBe("500 m");
  });
});

describe("PlanGrid row menu", () => {
  it("opens with Alt+M, filters fuzzily and runs the picked action", () => {
    renderGrid(SAMPLE.differentRounds!);
    const name = screen.getByTestId("plan-name-bu");
    fireEvent.keyDown(name, { key: "m", code: "KeyM", altKey: true });
    const menu = screen.getByTestId("plan-row-menu");
    const filter = within(menu).getByRole("combobox");
    type(filter, "supr");
    expect(within(menu).getAllByRole("option")[0]).toHaveTextContent("Superset με την από πάνω");
    fireEvent.keyDown(filter, { key: "Enter" });
    expect(screen.queryByTestId("plan-row-menu")).not.toBeInTheDocument();
    const [ro, bu] = plan().blocks[0]!;
    expect(bu!.group).toBeTruthy();
    expect(bu!.group).toBe(ro!.group);
    expect(screen.getByTestId(`plan-struct-${ro!.group}`)).toHaveTextContent("Superset");
  });

  it("adds a parameter column (Alt+P) and removes it from the menu", () => {
    renderGrid(SAMPLE.differentRounds!);
    fireEvent.keyDown(screen.getByTestId("plan-name-ro"), { key: "p", code: "KeyP", altKey: true });
    const menu = screen.getByTestId("plan-row-menu");
    expect(menu).toHaveAttribute("data-mode", "measure");
    type(within(menu).getByRole("combobox"), "rpe");
    fireEvent.keyDown(within(menu).getByRole("combobox"), { key: "Enter" });
    expect(plan().blocks[0]![0]!.extra).toEqual(["rpe"]);
    type(cell("ro", "same", "rpe"), "8");
    expect(screen.getByTestId("plan-cell-ro-same-rpe-field")).toHaveTextContent("/10");
    type(cell("ro", "same", "rpe"), "12");
    expect(cell("ro", "same", "rpe")).toHaveAttribute("aria-invalid", "true");

    fireEvent.click(screen.getByTestId("plan-row-more-ro"));
    fireEvent.mouseDown(within(screen.getByTestId("plan-row-menu")).getByText("Αφαίρεση: RPE"));
    expect(plan().blocks[0]![0]!.extra).toEqual([]);
    expect(screen.queryByTestId("plan-cell-ro-same-rpe")).not.toBeInTheDocument();
  });

  it("sets a structure with Alt+T and shows its header row with fields", () => {
    renderGrid(emptySets());
    fireEvent.keyDown(screen.getByTestId("plan-name-a"), { key: "t", code: "KeyT", altKey: true });
    const menu = screen.getByTestId("plan-row-menu");
    fireEvent.mouseDown(within(menu).getByText("Cluster"));
    expect(plan().structs?.a).toEqual({ kind: "cluster", clusters: "3", intra: "15″" });
    expect(screen.getByTestId("plan-struct-a")).toHaveTextContent("το σετ σπάει σε κομμάτια");
  });

  it("closes on Escape and on a press outside", () => {
    renderGrid(emptySets());
    fireEvent.click(screen.getByTestId("plan-row-more-a"));
    expect(screen.getByTestId("plan-row-menu")).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByTestId("plan-row-menu")).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId("plan-row-more-a"));
    fireEvent.pointerDown(document.body);
    expect(screen.queryByTestId("plan-row-menu")).not.toBeInTheDocument();
  });

  it("adds a rest row after the exercise and deletes rows from the menu", () => {
    renderGrid(emptySets());
    fireEvent.keyDown(screen.getByTestId("plan-name-a"), { key: "r", code: "KeyR", altKey: true });
    const rows = plan().blocks[0]!;
    expect(rows.map((r) => r.kind)).toEqual(["ex", "rest"]);
    expect(rows[1]!.cells[0]).toEqual({ d: "30″" });
    fireEvent.click(screen.getByTestId(`plan-row-more-${rows[1]!.id}`));
    fireEvent.mouseDown(within(screen.getByTestId("plan-row-menu")).getByText("Διαγραφή"));
    expect(plan().blocks[0]!.map((r) => r.kind)).toEqual(["ex"]);
  });
});

describe("PlanGrid keyboard", () => {
  beforeEach(() => {
    vi.useRealTimers();
  });

  it("adds a row on Enter, deletes an empty one on Backspace and moves with the arrows", async () => {
    renderGrid(SAMPLE.differentRounds!);
    const ro = screen.getByTestId("plan-name-ro");
    ro.focus();
    fireEvent.keyDown(ro, { key: "Enter" });
    const added = plan().blocks[0]![1]!;
    expect(added.name).toBe("");
    await act(async () => {});
    expect(document.activeElement).toBe(screen.getByTestId(`plan-name-${added.id}`));

    fireEvent.keyDown(document.activeElement!, { key: "Backspace" });
    expect(plan().blocks[0]!.map((r) => r.id)).toEqual(["ro", "bu"]);

    const dose = cell("ro", "same", "d");
    dose.focus();
    fireEvent.keyDown(dose, { key: "ArrowDown" });
    expect(document.activeElement).toBe(cell("bu", "same", "d"));
    fireEvent.keyDown(document.activeElement!, { key: "ArrowUp" });
    expect(document.activeElement).toBe(dose);
  });

  it("moves between sets of the Σετ grid in the same column", () => {
    renderGrid(SAMPLE.superset!);
    const from = cell("ke", 2, "d");
    from.focus();
    fireEvent.keyDown(from, { key: "ArrowDown" });
    expect(document.activeElement).toBe(cell("cr", 2, "d"));
  });

  it("adds a different round with Alt+S, labelled with the rounds it runs in", async () => {
    renderGrid(SAMPLE.differentRounds!);
    fireEvent.keyDown(screen.getByTestId("plan-name-ro"), { key: "s", code: "KeyS", altKey: true });
    expect(plan().blocks).toHaveLength(3);
    expect(screen.getByTestId("plan-box-0")).toHaveTextContent("Γύρος 1, 4");
    expect(screen.getByTestId("plan-box-2")).toHaveTextContent("Γύρος 3");
    await act(async () => {});
    expect(document.activeElement).toBe(screen.getByTestId(`plan-name-${plan().blocks[2]![0]!.id}`));
  });

  it("suggests exercise names fuzzily from the WOD and the library; Enter picks", () => {
    renderGrid(emptySets());
    const name = screen.getByTestId("plan-name-a");
    type(name, "dedlift");
    const list = screen.getByRole("listbox");
    expect(within(list).getAllByRole("option")[0]).toHaveTextContent("Deadlift");
    fireEvent.keyDown(name, { key: "Enter" });
    expect(plan().blocks[0]![0]).toMatchObject({ name: "Deadlift", exerciseRef: "lib-dl" });
    expect(plan().blocks[0]).toHaveLength(1);
  });

  it("opens a note line with Alt+N", async () => {
    renderGrid(emptySets());
    fireEvent.keyDown(screen.getByTestId("plan-name-a"), { key: "n", code: "KeyN", altKey: true });
    await act(async () => {});
    const note = screen.getByTestId("plan-note-a");
    expect(document.activeElement).toBe(note);
    type(note, "με ζώνη");
    expect(plan().blocks[0]![0]!.note).toBe("με ζώνη");
  });
});

describe("PlanGrid layout", () => {
  it("switches to phone cards (sets as rows) when the grid is narrow", () => {
    vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(390);
    renderGrid(SAMPLE.sets!);
    expect(screen.getByTestId("plan-grid")).toHaveAttribute("data-layout", "phone");
    // one line per set, the row's lines as columns
    const rows = screen.getByTestId("plan-row-sq").querySelectorAll("tbody tr");
    expect(rows).toHaveLength(4);
    expect(within(rows[1] as HTMLElement).getByTestId("plan-cell-sq-1-l")).toBeInTheDocument();
  });

  it("keeps the wide grid when there is room", () => {
    vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(900);
    renderGrid(SAMPLE.sets!);
    expect(screen.getByTestId("plan-grid")).toHaveAttribute("data-layout", "wide");
    expect(screen.getByTestId("plan-row-sq").tagName).toBe("TR");
  });

  it("shows the interrupt lane when the add-on is on", () => {
    renderGrid(SAMPLE.forTimeInterrupt!);
    expect(screen.getByTestId("plan-interrupt")).toHaveTextContent("Διακοπή · κάθε 2:00");
    fireEvent.click(screen.getByTestId("plan-add-exercise-int"));
    expect(plan().interrupt).toHaveLength(2);
  });
});
