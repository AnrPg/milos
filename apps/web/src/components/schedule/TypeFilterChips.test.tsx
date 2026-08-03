import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { TypeFilterChips } from "./TypeFilterChips";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

describe("TypeFilterChips", () => {
  it("does not render a filter when only one active class type exists", () => {
    render(
      <TypeFilterChips
        classTypes={[{ id: "strength", name: "Strength", slug: "strength", sort_order: 1, archived_at: null }]}
        value={[]}
        onChange={() => undefined}
      />,
    );

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });
});
