"use client";

import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";

export type FolderOption = { id: string | null; label: string; disabled?: boolean };

/** Folder picker used to move or copy a workout, or to move a folder. */
export function LibraryTransferDialog({
  title,
  confirmLabel,
  options,
  initialFolderId,
  busy,
  onCancel,
  onConfirm,
}: {
  title: string;
  confirmLabel: string;
  options: FolderOption[];
  initialFolderId: string | null;
  busy: boolean;
  onCancel: () => void;
  onConfirm: (folderId: string | null) => void;
}) {
  const i18n = useUiTranslations();
  const [selected, setSelected] = useState(initialFolderId ?? "");

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" style={{ background: "var(--scrim)" }} onClick={onCancel} role="presentation">
      <form
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="w-full max-w-md rounded-[1.5rem] p-5 shadow-[var(--shadow-lg)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(event) => event.stopPropagation()}
        onSubmit={(event) => {
          event.preventDefault();
          onConfirm(selected || null);
        }}
      >
        <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{title}</h2>
        <label className="mt-4 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("featureDestinationFolder")}
          <select
            autoFocus
            className="mt-2 w-full rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={selected}
            onChange={(event) => setSelected(event.target.value)}
          >
            {options.map((option) => (
              <option key={option.id ?? "root"} value={option.id ?? ""} disabled={option.disabled}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <div className="mt-5 flex justify-end gap-2">
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={onCancel}>
            {i18n("cancel77dfd21")}
          </button>
          <button type="submit" disabled={busy} className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {confirmLabel}
          </button>
        </div>
      </form>
    </div>
  );
}
