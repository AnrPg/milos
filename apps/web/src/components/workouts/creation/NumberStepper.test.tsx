import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { NumberStepper } from "./NumberStepper";

describe("NumberStepper", () => {
  it("allows a temporarily empty integer while the field is being edited", () => {
    const onChange = vi.fn();
    render(<NumberStepper value={12} onChange={onChange} min={1} />);

    const input = screen.getByRole("spinbutton");
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "" } });

    expect(input).toHaveValue(null);
    expect(onChange).not.toHaveBeenCalled();

    fireEvent.blur(input);
    expect(onChange).toHaveBeenCalledWith(1);
  });
});
