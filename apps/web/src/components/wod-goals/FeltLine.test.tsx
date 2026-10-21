import { render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import en from "../../../messages/en.json";

import { FeltLine } from "./FeltLine";

function wrap(ui: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {ui}
    </NextIntlClientProvider>,
  );
}

describe("FeltLine", () => {
  it("lists felt muscles, then qualities", () => {
    wrap(<FeltLine felt={{ muscles: ["quadriceps"], qualities: ["stamina"] }} />);
    const line = screen.getByTestId("journal-felt-line");
    expect(line.textContent).toMatch(/^Felt: /);
    expect(line.textContent).toContain(en.Anatomy.muscle.quadriceps);
    expect(line.textContent).toContain(en.Anatomy.quality.stamina);
  });

  it("renders nothing without feedback", () => {
    const { container } = wrap(<FeltLine felt={null} />);
    expect(container.textContent).toBe("");
  });
});
