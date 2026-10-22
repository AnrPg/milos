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
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: note }, []);
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

describe("FinishWizard: ADR-179 text-section scores", () => {
  it("asks for each score the coach set, by name, and sends them as numbers", () => {
    const onConfirm = vi.fn();
    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        freeText
        textSections={[
          {
            id: "s1",
            title: "Strength",
            body: "Back squat",
            preset: null,
            metrics: [{ key: "top-set", label: "Top set", kind: "load" }],
          },
          { id: "s2", title: "", body: "Run", preset: null, metrics: [] },
          {
            id: "s3",
            title: "",
            body: "AMRAP",
            preset: null,
            metrics: [
              { key: "rounds", label: "Rounds", kind: "rounds" },
              { key: "time", label: "Time", kind: "time" },
            ],
          },
        ]}
        isSaving={false}
        feedback={null}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.change(screen.getByRole("textbox", { name: "Strength · Top set" }), { target: { value: "102,5" } });
    fireEvent.change(screen.getByRole("textbox", { name: "textSectionNumber · Rounds" }), { target: { value: "7" } });
    const time = screen.getByRole("textbox", { name: "textSectionNumber · Time" });
    fireEvent.change(time, { target: { value: "5:3x" } });
    expect(time).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByRole("button", { name: "next2f04eb1" })).toBeDisabled();
    fireEvent.change(time, { target: { value: "5:30" } });

    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    expect(screen.getByText("Strength · Top set")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "saveDone3614269" }));
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: null }, [
      { section_id: "s1", metric_key: "top-set", value: 102.5 },
      { section_id: "s3", metric_key: "rounds", value: 7 },
      { section_id: "s3", metric_key: "time", value: 330 },
    ]);
  });
});
