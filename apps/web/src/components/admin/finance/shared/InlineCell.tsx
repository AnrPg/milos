"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";

type InlineCellProps = {
  value: string;
  display?: string;
  type?: "text" | "number" | "date";
  onSave: (value: string) => void;
  placeholder?: string;
  dimmed?: boolean;
  warn?: boolean;
};

export function InlineCell({ value, display, type = "text", onSave, placeholder, dimmed, warn }: InlineCellProps) {
  
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (editing) inputRef.current?.focus();
  }, [editing]);

  function commit() {
    setEditing(false);
    if (draft !== value) onSave(draft);
  }

  function cancel() {
    setEditing(false);
    setDraft(value);
  }

  if (editing) {
    return (
      <input
        ref={inputRef}
        className="w-full rounded-[0.8rem] px-2 py-1 text-sm outline-none"
        style={{ background: "var(--panel)", border: "1px solid var(--primary)", color: "var(--text)", minWidth: "7rem" }}
        type={type}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit();
          if (e.key === "Escape") cancel();
        }}
      />
    );
  }

  const shown = display ?? value;

  return (
    <button
      className="rounded-[0.8rem] px-2 py-1 text-start text-sm transition-colors hover:opacity-80"
      style={{
        color: warn ? "var(--primary-strong)" : dimmed ? "var(--dim)" : "var(--text)",
        background: "transparent",
        borderBottom: "1px dashed var(--border)",
        minWidth: "7rem",
      }}
      onClick={() => {
        setDraft(value);
        setEditing(true);
      }}
      type="button"
    >
      {shown || <span style={{ color: "var(--dim)" }}>{placeholder ?? "—"}</span>}
    </button>
  );
}

export function InlineToggle({
  value,
  options,
  onSave,
}: {
  value: string;
  options: Array<{ value: string; label: string; accent?: boolean }>;
  onSave: (value: string) => void;
}) {
  const i18n = useUiTranslations();
  const current = options.find((o) => o.value === value) ?? options[0];
  const next = options[(options.indexOf(current) + 1) % options.length];

  return (
    <button
      className="rounded-full px-3 py-1 text-xs font-semibold"
      style={{
        background: current.accent ? "color-mix(in srgb, var(--primary) 12%, transparent)" : "var(--border)",
        color: current.accent ? "var(--primary)" : "var(--text-soft)",
        border: current.accent ? "1px solid color-mix(in srgb, var(--primary) 30%, transparent)" : "1px solid var(--border-strong)",
      }}
      onClick={() => onSave(next.value)}
      type="button"
      title={i18n("clickToSet1c43780") + (next.label)}
    >
      {current.label}
    </button>
  );
}
