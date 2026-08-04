import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { FinishWizard } from "./FinishWizard";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

describe("FinishWizard free-text modifications", () => {
  it("collects one multiline modification patch and previews it as blob text", () => {
    const onConfirm = vi.fn();
    const note = "Used a lighter sandbag.\nStopped after four rounds.";

    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        initialModifications={[]}
        freeText
        isSaving={false}
        feedback={null}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    fireEvent.change(screen.getByRole("textbox"), { target: { value: note } });
    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));

    expect(screen.getByText(/Used a lighter sandbag/)).toHaveClass("whitespace-pre-wrap");

    fireEvent.click(screen.getByRole("button", { name: "saveDone3614269" }));
    expect(onConfirm).toHaveBeenCalledWith([], [
      expect.objectContaining({
        patch_id: "free-text:modification",
        type: "other",
        field: "note",
        section_id: "free_text",
        canonical_value: "",
        actual_value: note,
      }),
    ]);
  });
});
