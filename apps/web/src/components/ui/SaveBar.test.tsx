import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { SaveBar } from "./SaveBar";

function renderBar(props: Partial<Parameters<typeof SaveBar>[0]> = {}) {
  const handlers = { onUndo: vi.fn(), onRedo: vi.fn(), onCancel: vi.fn(), onSave: vi.fn() };
  const view = render(
    <NextIntlClientProvider locale="en" messages={en}>
      <SaveBar changes={2} canUndo canRedo={false} {...handlers} {...props} />
      <input aria-label="note" />
    </NextIntlClientProvider>,
  );
  return { ...handlers, ...view };
}

describe("SaveBar (ADR-276)", () => {
  it("stays hidden with nothing to save", () => {
    renderBar({ changes: 0, canUndo: false });
    expect(screen.queryByTestId("save-bar")).toBeNull();
  });

  it("counts the changes and wires every button", () => {
    const { onUndo, onCancel, onSave, onRedo } = renderBar();
    expect(screen.getByTestId("save-bar-count").textContent).toBe("2 unsaved changes");
    fireEvent.click(screen.getByRole("button", { name: "Undo" }));
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(screen.getByRole("button", { name: "Redo" })).toHaveProperty("disabled", true);
    expect([onUndo, onCancel, onSave].map((fn) => fn.mock.calls.length)).toEqual([1, 1, 1]);
    expect(onRedo).not.toHaveBeenCalled();
  });

  it("keeps undo and redo reachable after undoing back to no changes", () => {
    renderBar({ changes: 0, canUndo: false, canRedo: true });
    expect(screen.getByTestId("save-bar-count").textContent).toBe("No changes");
    expect(screen.getByRole("button", { name: "Save" })).toHaveProperty("disabled", true);
  });

  it("saves with Ctrl+S, undoes with Ctrl+Z and leaves undo to text fields", () => {
    const { onSave, onUndo } = renderBar();
    fireEvent.keyDown(document.body, { key: "s", ctrlKey: true });
    fireEvent.keyDown(document.body, { key: "z", metaKey: true });
    fireEvent.keyDown(screen.getByLabelText("note"), { key: "z", ctrlKey: true });
    expect(onSave).toHaveBeenCalledTimes(1);
    expect(onUndo).toHaveBeenCalledTimes(1);
  });

  it("says the save went through, then shows errors in place", () => {
    const { rerender } = renderBar({ changes: 0, canUndo: false, saved: true });
    expect(screen.getByRole("status").textContent).toBe("Changes saved.");
    rerender(
      <NextIntlClientProvider locale="en" messages={en}>
        <SaveBar changes={1} canUndo canRedo={false} onUndo={vi.fn()} onRedo={vi.fn()} onCancel={vi.fn()} onSave={vi.fn()} error="Could not save" />
      </NextIntlClientProvider>,
    );
    expect(screen.getByText("Could not save")).toBeTruthy();
    expect(screen.queryByRole("status")).toBeNull();
  });
});
