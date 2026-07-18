import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { HomeDisclosure } from "@/components/home/HomeDisclosure";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

describe("HomeDisclosure", () => {
  it("reveals and hides home-page history content", () => {
    render(
      <HomeDisclosure eyebrow="Training" title="WOD history" defaultOpen={false}>
        <p>Fran · 18 July</p>
      </HomeDisclosure>,
    );

    const toggle = screen.getByRole("button", { name: /WOD history/ });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByText("Fran · 18 July")).not.toBeInTheDocument();

    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByText("Fran · 18 July")).toBeInTheDocument();

    fireEvent.click(toggle);
    expect(screen.queryByText("Fran · 18 July")).not.toBeInTheDocument();
  });
});
