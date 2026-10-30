import { fireEvent, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import { AgeConfirmationField, MINIMUM_AGE } from "@/components/auth/AgeConfirmationField";

vi.mock("next-intl", () => {
  const translate = (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key;
  translate.rich = (key: string, tags: Record<string, (chunks: ReactNode) => ReactNode>) => (
    <>
      {key} {tags.terms("terms")} {tags.privacy("privacy")}
    </>
  );
  return { useTranslations: () => translate };
});

describe("AgeConfirmationField (ADR-267)", () => {
  it("asks only whether the person is 16 or older, with the terms and privacy policy one tap away", () => {
    const onChange = vi.fn();
    render(<AgeConfirmationField checked={false} onChange={onChange} />);

    expect(MINIMUM_AGE).toBe(16);
    const box = screen.getByLabelText('ageConfirmation:{"age":16}');
    expect(box).not.toBeChecked();
    expect(box).toHaveAttribute("aria-invalid", "false");
    expect(screen.getByRole("link", { name: "terms" })).toHaveAttribute("href", "/terms");
    expect(screen.getByRole("link", { name: "privacy" })).toHaveAttribute("href", "/privacy");

    fireEvent.click(box);
    expect(onChange).toHaveBeenCalledWith(true);
  });

  it("shows the error in the form, under the box", () => {
    render(<AgeConfirmationField checked={false} onChange={vi.fn()} errors={["minimumAgeRule"]} />);

    const box = screen.getByLabelText('ageConfirmation:{"age":16}');
    expect(box).toHaveAttribute("aria-invalid", "true");
    const note = screen.getByText("minimumAgeRule");
    expect(box.getAttribute("aria-describedby")).toBe(note.closest("[id]")?.id);
  });
});
