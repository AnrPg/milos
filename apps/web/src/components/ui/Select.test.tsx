import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";

import { Select } from "./Select";

function Controlled({ onValueChange = () => undefined }: { onValueChange?: (value: string) => void }) {
  const [value, setValue] = useState("b");
  return (
    <form data-testid="form">
      <Select
        aria-label="Letter"
        name="letter"
        value={value}
        onValueChange={(next) => {
          setValue(next);
          onValueChange(next);
        }}
      >
        <option value="a">Alpha</option>
        <optgroup label="Later">
          <option value="b">Bravo</option>
          <option value="c" disabled>
            Charlie
          </option>
          {["d"].map((letter) => (
            <option key={letter} value={letter}>
              Delta {1}
            </option>
          ))}
        </optgroup>
      </Select>
    </form>
  );
}

describe("ui/Select", () => {
  it("shows the chosen option and opens a themed listbox with groups", () => {
    render(<Controlled />);
    const trigger = screen.getByRole("combobox", { name: "Letter" });
    expect(trigger).toHaveTextContent("Bravo");
    expect(screen.queryByRole("listbox")).toBeNull();

    fireEvent.click(trigger);
    expect(trigger).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("listbox")).toBeInTheDocument();
    expect(screen.getByText("Later")).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Bravo" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("option", { name: "Charlie" })).toHaveAttribute("aria-disabled", "true");
  });

  it("picks with a click, reports the value and feeds the form", () => {
    const onValueChange = vi.fn();
    render(<Controlled onValueChange={onValueChange} />);
    fireEvent.click(screen.getByRole("combobox", { name: "Letter" }));
    fireEvent.click(screen.getByRole("option", { name: "Delta 1" }));

    expect(onValueChange).toHaveBeenCalledWith("d");
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(screen.getByRole("combobox", { name: "Letter" })).toHaveTextContent("Delta 1");
    const form = screen.getByTestId("form") as HTMLFormElement;
    expect(new FormData(form).get("letter")).toBe("d");
  });

  it("ignores disabled options and moves past them with the keyboard", () => {
    const onValueChange = vi.fn();
    render(<Controlled onValueChange={onValueChange} />);
    fireEvent.click(screen.getByRole("combobox", { name: "Letter" }));
    fireEvent.click(screen.getByRole("option", { name: "Charlie" }));
    expect(onValueChange).not.toHaveBeenCalled();

    const list = screen.getByRole("listbox");
    fireEvent.keyDown(list, { key: "ArrowDown" });
    fireEvent.keyDown(list, { key: "Enter" });
    expect(onValueChange).toHaveBeenCalledWith("d");
  });

  it("types ahead on the closed trigger like a native select", () => {
    const onValueChange = vi.fn();
    render(<Controlled onValueChange={onValueChange} />);
    fireEvent.keyDown(screen.getByRole("combobox", { name: "Letter" }), { key: "a" });
    expect(onValueChange).toHaveBeenCalledWith("a");
  });

  it("works uncontrolled from defaultValue", () => {
    render(
      <Select aria-label="Size" defaultValue="m">
        <option value="s">Small</option>
        <option value="m">Medium</option>
      </Select>,
    );
    const trigger = screen.getByRole("combobox", { name: "Size" });
    expect(trigger).toHaveTextContent("Medium");
    fireEvent.click(trigger);
    fireEvent.click(screen.getByRole("option", { name: "Small" }));
    expect(trigger).toHaveTextContent("Small");
  });
});
