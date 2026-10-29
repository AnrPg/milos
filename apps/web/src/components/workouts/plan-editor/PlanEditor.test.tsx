import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { PLAN_VERSION, type PlanRow, type PlanSection } from "@/lib/structured-plan";
import { usePlanEditorStore, type PlanEditorSection } from "@/stores/structured-plan";

import en from "../../../../messages/en.json";

import { PlanEditor } from "./PlanEditor";

// The shell is tested on its own: a bare grid of name fields stands in for agent 4's grid.
vi.mock("./grid", async () => {
  const { usePlanEditorStore: useStore } = await import("@/stores/structured-plan");
  return {
    PlanGrid: ({ sectionId }: { sectionId: string }) => {
      const sec = useStore((s) => s.sections.find((x) => x.id === sectionId));
      const updateRow = useStore((s) => s.updateRow);
      return (
        <div>
          {sec?.plan.blocks.flat().map((r) => (
            <input key={r.id} data-key={`r:${r.id}:name`} aria-label={r.id} value={r.name} onChange={(e) => updateRow(r.id, { name: e.target.value })} />
          ))}
        </div>
      );
    },
  };
});

const store = () => usePlanEditorStore.getState();
const row = (id: string, name = id): PlanRow => ({ id, kind: "ex", name, dose: "", load: "", cells: [], group: null });
const plan = (more: Partial<PlanSection> = {}): PlanSection => ({ v: PLAN_VERSION, flow: "sets", params: { sets: "4", rest: "90″" }, blocks: [[row("a", "Back Squat")]], score: "none", ...more });
const section = (id: string, more: Partial<PlanSection> = {}, name = ""): PlanEditorSection => ({ id, name, plan: plan(more) });

function renderEditor(levels?: { key: string; label: string }[]) {
  return render(
    <NextIntlClientProvider locale="en" messages={en} onError={() => {}} getMessageFallback={({ key, namespace }) => [namespace, key].filter(Boolean).join(".")}>
      <PlanEditor levels={levels} />
    </NextIntlClientProvider>,
  );
}

const active = () => document.activeElement as HTMLElement;
const key = (init: KeyboardEventInit & { key: string; code?: string }) => fireEvent.keyDown(active(), init);
const alt = (k: string, code?: string) => key({ key: k, code, altKey: true });

beforeEach(() => {
  store().load({ title: "Monday", note: "", sections: [section("s1", {}, "Strength"), section("s2", { flow: "for_time", params: { rounds: "3", cap: "" }, blocks: [[row("c", "Burpee")]], score: "time" })] });
});

describe("PlanEditor", () => {
  it("shows closed sections as one-line cards and opens one at a time", () => {
    renderEditor();
    const cards = screen.getAllByTestId("plan-section-card");
    expect(cards).toHaveLength(2);
    expect(cards[0]).toHaveTextContent("A");
    expect(cards[0]).toHaveTextContent("Strength");
    expect(cards[0]).toHaveTextContent("Back Squat");
    fireEvent.click(cards[0]);
    expect(screen.getByTestId("plan-open-section")).toBeInTheDocument();
    expect(screen.getAllByTestId("plan-section-card")).toHaveLength(1);
    expect(screen.getByTestId("plan-step-exercises")).toHaveAttribute("aria-current", "step");
    fireEvent.click(screen.getAllByTestId("plan-section-card")[0]);
    expect(screen.getAllByTestId("plan-open-section")).toHaveLength(1);
    expect(store().openId).toBe("s2");
  });

  it("walks a new section through the wizard by keyboard", () => {
    renderEditor();
    fireEvent.click(screen.getByTestId("plan-add-section"));
    const input = screen.getByTestId("plan-flow-input");
    expect(active()).toBe(input);
    expect(screen.getByTestId("plan-step-flow")).toHaveAttribute("aria-current", "step");

    // presets sit apart from flows, in their own box
    expect(within(screen.getByTestId("plan-presets")).getByTestId("plan-preset-option-tabata")).toBeInTheDocument();
    expect(within(screen.getByTestId("plan-presets")).queryByTestId("plan-flow-option-emom")).toBeNull();

    fireEvent.change(input, { target: { value: "tabta" } });
    expect(screen.getByTestId("plan-preset-option-tabata")).toHaveAttribute("aria-selected", "true");
    key({ key: "Enter" });
    const id = store().openId!;
    expect(store().sections.find((s) => s.id === id)!.plan).toMatchObject({ flow: "intervals", preset: "tabata" });

    // Χρόνος: Enter goes field by field, then to the next step
    expect(active()).toBe(screen.getByTestId("plan-param-work"));
    key({ key: "Enter" });
    expect(active()).toBe(screen.getByTestId("plan-param-off"));
    key({ key: "Enter" });
    expect(active()).toBe(screen.getByTestId("plan-param-rounds"));
    key({ key: "Enter" });
    expect(store().step).toBe(2);
    expect(screen.getByTestId("plan-step-exercises")).toHaveAttribute("aria-current", "step");

    alt("ArrowRight");
    expect(store().step).toBe(3);
    expect(active()).toHaveAttribute("role", "radio");
    alt("ArrowLeft");
    expect(store().step).toBe(2);
    alt("4", "Digit4");
    alt("ArrowRight");
    expect(store().openId).toBeNull();
    expect(active()).toHaveAttribute("data-k", `card:${id}`);
    expect(screen.getAllByTestId("plan-section-card")).toHaveLength(3);
  });

  it("drops a new section closed before a flow was picked", () => {
    renderEditor();
    fireEvent.click(screen.getByTestId("plan-add-section"));
    key({ key: "Escape" });
    expect(store().sections).toHaveLength(2);
  });

  it("ranks flows first and picks with the arrows", () => {
    renderEditor();
    fireEvent.click(screen.getByTestId("plan-add-section"));
    fireEvent.change(screen.getByTestId("plan-flow-input"), { target: { value: "emom" } });
    expect(screen.getByTestId("plan-flow-option-emom")).toHaveAttribute("aria-selected", "true");
    key({ key: "ArrowDown" });
    expect(screen.getByTestId("plan-flow-option-emom")).toHaveAttribute("aria-selected", "false");
    key({ key: "ArrowUp" });
    key({ key: "Enter" });
    expect(store().sections[2].plan.flow).toBe("emom");
  });

  it("skips the exercises step for rest", () => {
    renderEditor();
    act(() => store().openSection("s1", 0));
    fireEvent.change(screen.getByTestId("plan-flow-input"), { target: { value: "rest" } });
    key({ key: "Enter" });
    expect(store().sections[0].plan.flow).toBe("rest");
    expect(screen.getByTestId("plan-step-exercises")).toBeDisabled();
    alt("3", "Digit3");
    expect(store().step).toBe(1);
    alt("ArrowRight");
    expect(store().step).toBe(3);
  });

  it("shows each time field with its unit and reading, and flags what does not read", () => {
    renderEditor();
    act(() => store().openSection("s1", 1));
    const sets = screen.getByTestId("plan-param-sets");
    expect(sets.parentElement).toHaveTextContent("sets");
    const rest = screen.getByTestId("plan-param-rest") as HTMLInputElement;
    expect(rest.closest("label")).toHaveTextContent("=");
    fireEvent.change(rest, { target: { value: "abc" } });
    expect(rest).toHaveAttribute("aria-invalid", "true");
    expect(store().sections[0].plan.params.rest).toBe("abc");
    expect(screen.getByTestId("plan-sentence")).toBeInTheDocument();
  });

  it("says the other reading of an ambiguous time under its field", () => {
    renderEditor();
    act(() => store().openSection("s1", 1));
    const rest = screen.getByTestId("plan-param-rest") as HTMLInputElement;
    fireEvent.change(rest, { target: { value: "10" } });
    expect(rest.closest("label")).toHaveTextContent(/for the other unit write 10″/);
    fireEvent.change(rest, { target: { value: "1:30" } });
    expect(rest.closest("label")).not.toHaveTextContent(/other unit/);
  });

  it("adds and removes an add-on with its field", () => {
    renderEditor();
    act(() => store().openSection("s2", 1));
    fireEvent.click(screen.getByTestId("plan-mod-add-interrupt"));
    expect(active()).toBe(screen.getByTestId("plan-param-intEvery"));
    expect(screen.getByTestId("plan-timeline")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("plan-mod-remove-interrupt"));
    expect(screen.queryByTestId("plan-param-intEvery")).toBeNull();
  });

  it("changes the score with the arrows and keeps notes", () => {
    renderEditor([{ key: "scaled", label: "Scaled" }]);
    act(() => store().openSection("s2", 3));
    expect(screen.getByTestId("plan-score-time")).toHaveAttribute("aria-checked", "true");
    key({ key: "ArrowRight" });
    expect(store().sections[1].plan.score).toBe("rounds_reps");
    expect(active()).toBe(screen.getByTestId("plan-score-rounds_reps"));
    fireEvent.change(screen.getByTestId("plan-section-note"), { target: { value: "pace it" } });
    fireEvent.change(screen.getByTestId("plan-level-note-scaled"), { target: { value: "half reps" } });
    expect(store().sections[1].plan).toMatchObject({ note: "pace it", levelNotes: { scaled: "half reps" } });
  });

  it("adds, groups and deletes rows from the keyboard, with undo", () => {
    renderEditor();
    act(() => store().openSection("s2"));
    expect(active()).toHaveAttribute("data-key", "r:c:name");
    key({ key: "Enter" });
    const added = store().sections[1].plan.blocks[0][1];
    expect(active()).toHaveAttribute("data-key", `r:${added.id}:name`);
    alt("g", "KeyG");
    expect(store().sections[1].plan.blocks[0][1].group).toBeTruthy();
    alt("v", "KeyV");
    expect(store().findRow(added.id)!.row.perRound).toBe(true);
    act(() => store().setFocus(`r:${added.id}:name`));
    key({ key: "Backspace" });
    expect(store().findRow(added.id)).toBeNull();
    expect(screen.getByRole("status")).toHaveTextContent("Ctrl+Z");
    key({ key: "z", code: "KeyZ", ctrlKey: true });
    expect(store().findRow(added.id)).not.toBeNull();
    key({ key: "Z", code: "KeyZ", ctrlKey: true, shiftKey: true });
    expect(store().findRow(added.id)).toBeNull();
  });

  it("adds a different round with Alt+S and says when per-round is impossible", () => {
    renderEditor();
    act(() => store().openSection("s1"));
    alt("v", "KeyV");
    expect(screen.getByRole("status")).toHaveTextContent(en.PlanEditor.perRoundOnce);
    alt("s", "KeyS");
    expect(store().sections[0].plan.blocks).toHaveLength(2);
  });

  it("moves between closed cards and reorders them", () => {
    renderEditor();
    const [first] = screen.getAllByTestId("plan-section-card");
    first.focus();
    key({ key: "ArrowDown" });
    expect(active()).toHaveAttribute("data-k", "card:s2");
    alt("ArrowUp");
    expect(store().sections.map((s) => s.id)).toEqual(["s2", "s1"]);
    expect(active()).toHaveAttribute("data-k", "card:s2");
  });

  it("opens the shortcut sheet with ? and shows the hint line", () => {
    renderEditor();
    expect(screen.getByTestId("plan-hint")).toHaveTextContent("Shift+Enter");
    screen.getAllByTestId("plan-section-card")[0].focus();
    key({ key: "?" });
    expect(screen.getByRole("dialog")).toHaveTextContent(en.PlanEditor.sheet.superset);
    act(() => store().openSection("s1"));
    expect(screen.getByTestId("plan-hint")).toHaveTextContent("Alt+M");
  });

  it("does not open the sheet when ? is typed in a field", () => {
    renderEditor();
    screen.getByTestId("plan-title").focus();
    key({ key: "?" });
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});
