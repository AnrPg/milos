import { act, fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { usePlanEditorStore } from "@/stores/structured-plan";

import el from "../../../../../messages/el.json";

import { PlanEditor } from "../PlanEditor";
import { SAMPLE } from "./fixtures";

vi.mock("./useExerciseCatalog", () => ({ useExerciseCatalog: () => [] }));

const store = () => usePlanEditorStore.getState();
const plan = (id: string) => store().sections.find((s) => s.id === id)!.plan;

function renderEditor() {
  return render(
    <NextIntlClientProvider locale="el" messages={el} onError={() => {}} getMessageFallback={({ key, namespace }) => [namespace, key].filter(Boolean).join(".")}>
      <PlanEditor />
    </NextIntlClientProvider>,
  );
}

beforeEach(() => {
  store().load({ title: "", note: "", sections: [{ id: "s1", name: "", plan: structuredClone(SAMPLE.differentRounds!) }] });
  store().openSection("s1", 2);
});

describe("PlanGrid inside the editor shell", () => {
  it("adds exactly one row on Enter and one block on Alt+S, and undo takes them back", async () => {
    renderEditor();
    const name = screen.getByTestId("plan-name-ro");
    name.focus();
    fireEvent.keyDown(name, { key: "Enter" });
    expect(plan("s1").blocks[0]).toHaveLength(3);
    await act(async () => {});
    fireEvent.keyDown(document.activeElement!, { key: "s", code: "KeyS", altKey: true });
    expect(plan("s1").blocks).toHaveLength(3);
    act(() => store().undo());
    act(() => store().undo());
    expect(plan("s1").blocks).toHaveLength(2);
    expect(plan("s1").blocks[0]).toHaveLength(2);
  });

  it("keeps typing in one undo step and leaves Esc on a closed menu to the shell", () => {
    renderEditor();
    const dose = screen.getByTestId("plan-cell-ro-same-d");
    fireEvent.change(dose, { target: { value: "1000 m" } });
    fireEvent.change(dose, { target: { value: "1000 m" } });
    expect(plan("s1").blocks[0]![0]!.dose).toBe("1000 m");
    fireEvent.keyDown(dose, { key: "m", code: "KeyM", altKey: true });
    expect(screen.getByTestId("plan-row-menu")).toBeInTheDocument();
    // Esc closes the menu only, not the section
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByTestId("plan-row-menu")).not.toBeInTheDocument();
    expect(store().openId).toBe("s1");
  });
});
