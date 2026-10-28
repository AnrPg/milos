import { fireEvent, render, screen } from "@testing-library/react";
import { useRef, useState } from "react";
import { describe, expect, it } from "vitest";

import { Popover } from "./Popover";
import { Select } from "./Select";
import { chooseOption, press } from "./select-test-utils";

function MenuWithSelect() {
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState("");
  return (
    <div>
      <button ref={anchorRef} type="button" onClick={() => setOpen((v) => !v)}>
        Open menu
      </button>
      <button type="button">Elsewhere</button>
      <Popover anchorRef={anchorRef} open={open} onClose={() => setOpen(false)} role="dialog" ariaLabel="Menu">
        <Select aria-label="Package" value={value} onValueChange={setValue}>
          <option value="">Pick one</option>
          <option value="gold">Gold</option>
        </Select>
        <output>{value || "none"}</output>
      </Popover>
    </div>
  );
}

describe("ui/Popover", () => {
  it("keeps the menu open when an option of a Select inside it is pressed", () => {
    render(<MenuWithSelect />);
    press(screen.getByRole("button", { name: "Open menu" }));
    chooseOption(screen.getByRole("combobox", { name: "Package" }), "Gold");

    expect(screen.getByRole("dialog", { name: "Menu" })).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Package" })).toHaveTextContent("Gold");
    expect(screen.getByText("gold")).toBeInTheDocument();
  });

  it("still closes on a press outside, and Escape closes only the innermost layer", () => {
    render(<MenuWithSelect />);
    press(screen.getByRole("button", { name: "Open menu" }));
    press(screen.getByRole("combobox", { name: "Package" }));
    expect(screen.getByRole("listbox")).toBeInTheDocument();

    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(screen.getByRole("dialog", { name: "Menu" })).toBeInTheDocument();

    press(screen.getByRole("button", { name: "Elsewhere" }));
    expect(screen.queryByRole("dialog", { name: "Menu" })).toBeNull();
  });
});
