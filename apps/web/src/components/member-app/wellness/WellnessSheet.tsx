"use client";

import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

/** The bottom sheet every Ευεξία form opens in (centered on wider screens). */
export function WellnessSheet({
  title,
  subtitle,
  onClose,
  children,
}: {
  title: string;
  subtitle?: ReactNode;
  onClose: () => void;
  children: ReactNode;
}) {
  const t = useTranslations("MemberApp.wellness");
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  return (
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center sm:items-center"
      style={{ background: "rgba(0, 0, 0, 0.45)" }}
      onClick={onClose}
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="max-h-[92vh] w-full max-w-md overflow-y-auto rounded-t-3xl p-5 sm:rounded-3xl"
        style={{
          background: "var(--panel)",
          border: "1px solid var(--border)",
          paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))",
        }}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{title}</h2>
            {subtitle ? <p className="text-xs" style={{ color: "var(--dim)" }}>{subtitle}</p> : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t("close")}
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-lg"
            style={{ background: "var(--panel-raised)", color: "var(--dim)" }}
          >
            ×
          </button>
        </div>
        <div className="flex flex-col gap-4">{children}</div>
      </div>
    </div>
  );
}

export function SheetSection({ label, children }: { label: string; children: ReactNode }) {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {label}
      </legend>
      {children}
    </fieldset>
  );
}

/** A row of choice pills; one value, or several when `multiple`. */
export function Pills<T extends string | number>({
  options,
  selected,
  label,
  onToggle,
}: {
  options: T[];
  selected: T[];
  label: (value: T) => string;
  onToggle: (value: T) => void;
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {options.map((option) => {
        const on = selected.includes(option);
        return (
          <button
            key={String(option)}
            type="button"
            aria-pressed={on}
            onClick={() => onToggle(option)}
            className="min-h-10 rounded-full px-3.5 text-sm font-semibold"
            style={{
              background: on ? "var(--primary)" : "var(--panel-raised)",
              color: on ? "var(--bg)" : "var(--text)",
              border: "1px solid var(--border)",
            }}
          >
            {label(option)}
          </button>
        );
      })}
    </div>
  );
}

export function PrimaryButton({
  children,
  disabled,
  onClick,
  type = "button",
}: {
  children: ReactNode;
  disabled?: boolean;
  onClick?: () => void;
  type?: "button" | "submit";
}) {
  return (
    <button
      type={type}
      disabled={disabled}
      onClick={onClick}
      className="min-h-12 w-full rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
      style={{ background: "var(--primary)", color: "var(--bg)" }}
    >
      {children}
    </button>
  );
}

export function QuietButton({
  children,
  onClick,
  danger,
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 rounded-2xl px-4 text-sm font-semibold disabled:opacity-50"
      style={{ border: "1px solid var(--border)", color: danger ? "var(--danger)" : "var(--text)" }}
    >
      {children}
    </button>
  );
}

export function ErrorLine({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
      {message}
    </p>
  );
}
