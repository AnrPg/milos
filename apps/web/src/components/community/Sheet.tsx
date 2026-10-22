"use client";

import type { ReactNode } from "react";

import { Dialog } from "@/components/ui/Dialog";

/**
 * A bottom sheet (a centred dialog on wide screens): the shared dialog shell
 * with a scrolling body and an always-visible footer.
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
  return (
    <Dialog
      onClose={onClose}
      title={title}
      eyebrow={eyebrow}
      titleId={labelId}
      footer={footer ? <div className="flex w-full gap-2">{footer}</div> : undefined}
      variant="sheet"
      size="xl"
    >
      {children}
    </Dialog>
  );
}

/** The sheet's and page's main and secondary buttons. */
export function SheetButton({
  children,
  onClick,
  primary,
  spark,
  disabled,
  type = "button",
  form,
}: {
  children: ReactNode;
  onClick?: () => void;
  primary?: boolean;
  /** A go-now action (join): Spark instead of Dojo (ADR-182). */
  spark?: boolean;
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
        background: spark ? "var(--spark)" : primary ? "var(--primary)" : "var(--panel-raised)",
        color: spark ? "var(--spark-contrast)" : primary ? "var(--primary-contrast)" : "var(--text)",
        border: primary || spark ? "none" : "1px solid var(--border)",
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
