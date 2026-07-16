

import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

function TestDialog({ onClose }: { onClose: () => void }) {
  const ref = useModalFocusTrap<HTMLDivElement>(onClose);

  return (
    <div ref={ref} role="dialog" aria-modal="true" tabIndex={-1}>
      <button type="button">First</button>
      <button type="button">Last</button>
    </div>
  );
}

describe("useModalFocusTrap", () => {
  afterEach(() => {
    document.body.style.overflow = "";
    document.body.innerHTML = "";
  });

  it("traps focus, closes on escape, restores body overflow and previous focus", () => {
    const onClose = vi.fn();
    const launcher = document.createElement("button");
    launcher.textContent = "Open";
    document.body.appendChild(launcher);
    launcher.focus();

    const { unmount } = render(<TestDialog onClose={onClose} />);
    const first = screen.getByRole("button", { name: "First" });
    const last = screen.getByRole("button", { name: "Last" });

    expect(first).toHaveFocus();
    expect(document.body.style.overflow).toBe("hidden");

    last.focus();
    fireEvent.keyDown(document, { key: "Tab" });
    expect(first).toHaveFocus();

    first.focus();
    fireEvent.keyDown(document, { key: "Tab", shiftKey: true });
    expect(last).toHaveFocus();

    fireEvent.keyDown(document, { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(1);

    unmount();
    expect(document.body.style.overflow).toBe("");
    expect(launcher).toHaveFocus();
  });
});
