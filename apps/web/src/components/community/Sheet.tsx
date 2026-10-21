"use client";

import type { ReactNode } from "react";
import { createPortal } from "react-dom";

import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

/**
 * A bottom sheet (a centred dialog on wide screens), portalled to the body so
 * no card's stacking context clips it. Escape and the backdrop close it.
 */
export function Sheet({
  title,
  eyebrow,
  onClose,
  children,
  footer,
  labelId,
}: {
  title: string;
  eyebrow?: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  labelId: string;
}) {
  const dialog = useModalFocusTrap<HTMLElement>(onClose);
  return createPortal(
    <div
      className="fixed inset-0 z-[70] flex items-end justify-center sm:items-center"
      style={{ background: "var(--scrim)" }}
      onClick={onClose}
      role="presentation"
    >
      <section
        ref={dialog}
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelId}
        onClick={(event) => event.stopPropagation()}
        className="flex max-h-[92dvh] w-full max-w-xl flex-col rounded-t-3xl sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="flex justify-center pt-2.5 sm:hidden">
          <span aria-hidden="true" className="h-1 w-10 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <header className="px-5 pb-2 pt-3">
          {eyebrow ? (
            <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{eyebrow}</p>
          ) : null}
          <h2 id={labelId} className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{title}</h2>
        </header>
        <div className="flex-1 overflow-y-auto px-5 pb-4">{children}</div>
        {footer ? (
          <footer className="flex gap-2 border-t px-5 py-3" style={{ borderColor: "var(--border)" }}>
            {footer}
          </footer>
        ) : null}
      </section>
    </div>,
    document.body,
  );
}

/** The sheet's and page's main and secondary buttons. */
export function SheetButton({
  children,
  onClick,
  primary,
  disabled,
  type = "button",
  form,
}: {
  children: ReactNode;
  onClick?: () => void;
  primary?: boolean;
  disabled?: boolean;
  type?: "button" | "submit";
  form?: string;
}) {
  return (
    <button
      type={type}
      form={form}
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
      style={{
        background: primary ? "var(--primary)" : "var(--panel-raised)",
        color: primary ? "var(--primary-contrast)" : "var(--text)",
        border: primary ? "none" : "1px solid var(--border)",
      }}
    >
      {children}
    </button>
  );
}

/** A pill-shaped choice in a row of options (radio semantics). */
export function ChoicePill({
  selected,
  onSelect,
  children,
  hint,
}: {
  selected: boolean;
  onSelect: () => void;
  children: ReactNode;
  hint?: string;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      onClick={onSelect}
      className="flex min-h-11 flex-1 flex-col items-start justify-center rounded-2xl px-4 py-2 text-left"
      style={{
        background: selected ? "color-mix(in srgb, var(--primary) 14%, var(--panel))" : "var(--panel-raised)",
        border: `1px solid ${selected ? "var(--primary)" : "var(--border)"}`,
        color: "var(--text)",
      }}
    >
      <span className="text-sm font-bold">{children}</span>
      {hint ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{hint}</span> : null}
    </button>
  );
}

export function ErrorLine({ message }: { message: string | null }) {
  return message ? (
    <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{message}</p>
  ) : null;
}
