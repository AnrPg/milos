import { fireEvent, screen } from "@testing-library/react";

/**
 * Presses an element the way a pointer does: pointerdown, mousedown, then
 * click. A bare click skips the press events that outside-press handlers
 * listen to, which hid a ledger menu closing before its Select could pick.
 */
export function press(element: HTMLElement) {
  fireEvent.pointerDown(element);
  fireEvent.mouseDown(element);
  fireEvent.pointerUp(element);
  fireEvent.mouseUp(element);
  fireEvent.click(element);
}

/** Opens a ui/Select and picks the option with this accessible name (tests only). */
export function chooseOption(trigger: HTMLElement, name: string | RegExp) {
  press(trigger);
  press(screen.getByRole("option", { name }));
}

/** Opens a ui/Select and picks the option with this value (tests only). */
export function chooseValue(trigger: HTMLElement, value: string) {
  press(trigger);
  const option = document.querySelector<HTMLElement>(`[role="option"][data-value="${CSS.escape(value)}"]`);
  if (!option) throw new Error(`No option with value "${value}"`);
  press(option);
}
