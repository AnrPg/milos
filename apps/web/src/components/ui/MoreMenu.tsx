"use client";

import { useRef, useState } from "react";

import { Popover } from "./Popover";

export type MoreMenuItem = {
  label: string;
  onSelect: () => void;
  /** Destructive items (cancel, delete) show in the danger colour, after a divider. */
  tone?: "danger";
  disabled?: boolean;
  testId?: string;
};

/**
 * ⋯ with a short menu of the less common actions on a card, post or person.
 * Action rows keep one or two visible buttons and put the rest here, so a row
 * never overflows its card on a narrow screen or in a long language.
 * Destructive items always come last, below a divider.
 */
export function MoreMenu({
  label,
  items,
  testId,
  variant = "plain",
}: {
  /** Accessible name of the ⋯ button and of the menu. */
  label: string;
  items: MoreMenuItem[];
  testId?: string;
  /** `pill` matches the rounded action buttons next to it on a card. */
  variant?: "plain" | "pill";
}) {
  const [open, setOpen] = useState(false);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const regular = items.filter((item) => item.tone !== "danger");
  const danger = items.filter((item) => item.tone === "danger");
  if (items.length === 0) return null;

  const renderItem = (item: MoreMenuItem) => (
    <li key={item.label} role="none">
      <button
        type="button"
        role="menuitem"
        disabled={item.disabled}
        data-testid={item.testId}
        onClick={() => {
          setOpen(false);
          item.onSelect();
        }}
        className="block min-h-11 w-full px-4 text-start text-sm font-semibold disabled:opacity-50"
        style={{ color: item.tone === "danger" ? "var(--danger)" : "var(--text)" }}
      >
        {item.label}
      </button>
    </li>
  );

  return (
    <div className="relative shrink-0">
      <button
        ref={buttonRef}
        type="button"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        data-testid={testId}
        onClick={() => setOpen((value) => !value)}
        className={
          variant === "pill"
            ? "flex h-10 min-w-10 items-center justify-center rounded-full px-3 text-lg font-bold leading-none"
            : "flex h-11 w-11 items-center justify-center rounded-full text-lg font-bold"
        }
        style={variant === "pill" ? { background: "var(--card)", color: "var(--text-soft)" } : { color: "var(--dim)" }}
      >
        <span aria-hidden="true">⋯</span>
      </button>
      <Popover
        anchorRef={buttonRef}
        open={open}
        onClose={() => setOpen(false)}
        align="end"
        minWidth={180}
        className="rounded-2xl py-1 shadow-lg"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <ul role="menu" aria-label={label}>
          {regular.map(renderItem)}
          {regular.length > 0 && danger.length > 0 ? (
            <li role="separator" className="my-1 h-px" style={{ background: "var(--border)" }} />
          ) : null}
          {danger.map(renderItem)}
        </ul>
      </Popover>
    </div>
  );
}
