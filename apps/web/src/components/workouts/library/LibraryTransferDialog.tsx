"use client";

import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";
import { Dialog } from "@/components/ui/Dialog";

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
    <Dialog
      onClose={onCancel}
      title={title}
      ariaLabel={title}
      size="md"
      variant="center"
      onSubmit={(event) => {
          event.preventDefault();
          onConfirm(selected || null);
        }}
      footer={
        <div className="w-full flex justify-end gap-2">
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={onCancel}>
            {i18n("cancel77dfd21")}
          </button>
          <button type="submit" disabled={busy} className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {confirmLabel}
          </button>
        </div>
      }
    >
        
        <label className="block text-sm font-semibold" style={{ color: "var(--muted)" }}>
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
    </Dialog>
  );
}
