import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { BackButton, BackLink } from "./BackLink";

describe("BackLink", () => {
  it("draws one hidden arrow and names the link by its label", () => {
    render(<BackLink href="/admin/users">Χρήστες</BackLink>);
    const link = screen.getByRole("link", { name: "Χρήστες" });
    expect(link).toHaveAttribute("href", "/admin/users");
    expect(link.textContent?.match(/←/g)).toHaveLength(1);
    expect(link.querySelector('[aria-hidden="true"]')).toHaveTextContent("←");
  });

  it("is a plain button for back steps that are not pages", () => {
    const onClick = vi.fn();
    render(<BackButton onClick={onClick}>Πίσω</BackButton>);
    const button = screen.getByRole("button", { name: "Πίσω" });
    expect(button).toHaveAttribute("type", "button");
    button.click();
    expect(onClick).toHaveBeenCalledOnce();
    expect(button.textContent?.match(/←/g)).toHaveLength(1);
  });
});
