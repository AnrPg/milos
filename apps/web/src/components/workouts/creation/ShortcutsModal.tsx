"use client";

import { useEffect } from "react";

const SHORTCUTS = [
  { keys: "Alt + E", description: "Add exercise to selected section" },
  { keys: "Alt + N", description: "Add new section" },
  { keys: "?", description: "Show this shortcuts panel" },
];

export function ShortcutsModal({ onClose }: { onClose: () => void }) {
  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        className="w-full max-w-sm rounded-[2rem] p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="mb-5 flex items-center justify-between">
          <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>
            Keyboard Shortcuts
          </h2>
          <button type="button" onClick={onClose} style={{ color: "var(--dim)" }}>✕</button>
        </div>
        <div className="space-y-3">
          {SHORTCUTS.map(({ keys, description }) => (
            <div key={keys} className="flex items-center justify-between gap-4">
              <span className="text-sm" style={{ color: "var(--muted)" }}>{description}</span>
              <kbd
                className="shrink-0 rounded-lg px-2.5 py-1 text-xs font-semibold"
                style={{ background: "var(--bg)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
              >
                {keys}
              </kbd>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
