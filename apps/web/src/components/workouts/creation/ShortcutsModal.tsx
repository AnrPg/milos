"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect } from "react";

export function ShortcutsModal({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  const SHORTCUTS = [
    { keys: i18n("altE997c3b7"), description: i18n("addExerciseToSelectedSection23b8456") },
    { keys: i18n("altNb530fec"), description: i18n("addNewSectione0512f7") },
    { keys: "?", description: i18n("showThisShortcutsPanel838be9e") },
  ];
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
            {i18n("keyboardShortcutsb465751")}
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
