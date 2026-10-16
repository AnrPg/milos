import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { FinishWizard } from "./FinishWizard";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useFormatter: () => ({ dateTime: () => "" }),
}));

describe("FinishWizard free-text comments", () => {
  it("collects one multiline comment on the whole workout and previews it as written", () => {
    const onConfirm = vi.fn();
    const note = "Used a lighter sandbag.\nStopped after four rounds.";

    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        pendingCommentIds={[]}
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
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: note });
  });

  it("offers a way back to the workout from the first step", () => {
    const onCancel = vi.fn();

    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        pendingCommentIds={[]}
        isSaving={false}
        feedback={null}
        onConfirm={vi.fn()}
        onCancel={onCancel}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "backToWorkoutLabel" }));
    expect(onCancel).toHaveBeenCalledTimes(1);
  });
});
