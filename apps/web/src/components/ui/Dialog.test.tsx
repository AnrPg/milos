import { useRef, useState } from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { Dialog } from "./Dialog";
import { Popover } from "./Popover";

describe("Dialog", () => {
  afterEach(() => {
    document.body.style.overflow = "";
  });

  it("portals into the body on the modal layer with a scrolling body and a separate footer", () => {
    render(
      <div style={{ transform: "translateZ(0)" }} data-testid="host">
        <Dialog onClose={() => {}} title="Create series" closeLabel="Close" footer={<button type="button">Save</button>}>
          <p>Fields</p>
        </Dialog>
      </div>,
    );

    const dialog = screen.getByRole("dialog", { name: "Create series" });
    expect(screen.getByTestId("host")).not.toContainElement(dialog);
    expect(dialog.parentElement).toHaveStyle({ zIndex: "var(--z-modal)" });
    expect(dialog.className).toContain("max-h-full");

    const body = screen.getByText("Fields").parentElement!;
    expect(body.className).toContain("overflow-y-auto");
    const footer = screen.getByRole("button", { name: "Save" }).closest("footer")!;
    expect(body).not.toContainElement(footer);
    expect(screen.getByRole("button", { name: "Close" })).toBeInTheDocument();
  });

  it("closes from Escape, the close button and a press on the backdrop, but not from inside", () => {
    const onClose = vi.fn();
    render(
      <Dialog onClose={onClose} title="Title" closeLabel="Close">
        <p>Inside</p>
      </Dialog>,
    );

    fireEvent.pointerDown(screen.getByText("Inside"));
    fireEvent.click(screen.getByText("Inside"));
    expect(onClose).not.toHaveBeenCalled();

    fireEvent.keyDown(document, { key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    const backdrop = screen.getByRole("dialog").parentElement!;
    fireEvent.pointerDown(backdrop);
    fireEvent.click(backdrop);
    expect(onClose).toHaveBeenCalledTimes(3);
  });

  it("stays open while not dismissible", () => {
    const onClose = vi.fn();
    render(
      <Dialog onClose={onClose} title="Saving" closeLabel="Close" dismissible={false}>
        <p>Busy</p>
      </Dialog>,
    );
    fireEvent.keyDown(document, { key: "Escape" });
    const backdrop = screen.getByRole("dialog").parentElement!;
    fireEvent.pointerDown(backdrop);
    fireEvent.click(backdrop);
    expect(onClose).not.toHaveBeenCalled();
  });

  it("submits as a form from a footer submit button", () => {
    const onSubmit = vi.fn((event: { preventDefault: () => void }) => event.preventDefault());
    render(
      <Dialog onClose={() => {}} title="Form" closeLabel="Close" onSubmit={onSubmit} footer={<button type="submit">Save</button>}>
        <input aria-label="Name" />
      </Dialog>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(onSubmit).toHaveBeenCalledTimes(1);
  });
});

function Menu({ onDialogClose }: { onDialogClose: () => void }) {
  const [open, setOpen] = useState(true);
  const anchor = useRef<HTMLButtonElement>(null);
  return (
    <Dialog onClose={onDialogClose} title="Host" closeLabel="Close">
      <button ref={anchor} type="button" onClick={() => setOpen((value) => !value)}>
        More
      </button>
      <Popover anchorRef={anchor} open={open} onClose={() => setOpen(false)} role="menu" ariaLabel="Actions">
        <button type="button">Rename</button>
      </Popover>
    </Dialog>
  );
}

describe("Popover", () => {
  afterEach(() => {
    document.body.style.overflow = "";
  });

  it("floats above dialogs on the popover layer and Escape closes only the menu", () => {
    const onDialogClose = vi.fn();
    render(<Menu onDialogClose={onDialogClose} />);

    const menu = screen.getByRole("menu", { name: "Actions" });
    expect(menu).toHaveStyle({ zIndex: "var(--z-popover)", position: "fixed" });
    expect(screen.getByRole("dialog")).not.toContainElement(menu);

    fireEvent.pointerDown(screen.getByRole("button", { name: "Rename" }));
    expect(screen.getByRole("menu")).toBeInTheDocument();

    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
    expect(onDialogClose).not.toHaveBeenCalled();
  });

  it("closes on a press outside the menu and its trigger", () => {
    render(<Menu onDialogClose={() => {}} />);
    fireEvent.pointerDown(screen.getByRole("heading", { name: "Host" }));
    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
  });
});
