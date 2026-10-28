import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { MoreMenu } from "./MoreMenu";

describe("ui/MoreMenu", () => {
  it("opens a menu with destructive items last, below a divider, and closes on choice", () => {
    const duplicate = vi.fn();
    const remove = vi.fn();
    render(
      <MoreMenu
        label="More actions for this class"
        items={[
          { label: "Delete", onSelect: remove, tone: "danger" },
          { label: "Duplicate", onSelect: duplicate },
        ]}
      />,
    );

    const trigger = screen.getByRole("button", { name: "More actions for this class" });
    expect(trigger).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(trigger);
    expect(trigger).toHaveAttribute("aria-expanded", "true");

    const menu = screen.getByRole("menu", { name: "More actions for this class" });
    expect(within(menu).getAllByRole("menuitem").map((item) => item.textContent)).toEqual(["Duplicate", "Delete"]);
    expect(within(menu).getByRole("separator")).toBeInTheDocument();
    expect(within(menu).getByRole("menuitem", { name: "Delete" })).toHaveStyle({ color: "var(--danger)" });

    fireEvent.click(within(menu).getByRole("menuitem", { name: "Duplicate" }));
    expect(duplicate).toHaveBeenCalledOnce();
    expect(remove).not.toHaveBeenCalled();
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
  });

  it("closes on Escape and renders nothing without items", () => {
    const { rerender } = render(<MoreMenu label="More" items={[{ label: "Report", onSelect: () => undefined }]} />);
    fireEvent.click(screen.getByRole("button", { name: "More" }));
    expect(screen.getByRole("menu")).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();

    rerender(<MoreMenu label="More" items={[]} />);
    expect(screen.queryByRole("button", { name: "More" })).not.toBeInTheDocument();
  });

  it("leaves no separator when every item is of one kind", () => {
    render(<MoreMenu label="More" items={[{ label: "Remove", onSelect: () => undefined, tone: "danger" }]} />);
    fireEvent.click(screen.getByRole("button", { name: "More" }));
    expect(screen.queryByRole("separator")).not.toBeInTheDocument();
  });
});
