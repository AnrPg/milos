import { fireEvent, screen } from "@testing-library/react";

/** Opens a ui/Select and picks the option with this accessible name (tests only). */
export function chooseOption(trigger: HTMLElement, name: string | RegExp) {
  fireEvent.click(trigger);
  fireEvent.click(screen.getByRole("option", { name }));
}

/** Opens a ui/Select and picks the option with this value (tests only). */
export function chooseValue(trigger: HTMLElement, value: string) {
  fireEvent.click(trigger);
  const option = document.querySelector<HTMLElement>(`[role="option"][data-value="${CSS.escape(value)}"]`);
  if (!option) throw new Error(`No option with value "${value}"`);
  fireEvent.click(option);
}
