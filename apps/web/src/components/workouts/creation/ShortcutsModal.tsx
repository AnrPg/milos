"use client";





import {useUiTranslations} from "@/i18n/ui";
import { Dialog } from "@/components/ui/Dialog";

export function ShortcutsModal({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  const SHORTCUTS = [
    { keys: i18n("altE997c3b7"), description: i18n("addExerciseToSelectedSection23b8456") },
    { keys: i18n("altNb530fec"), description: i18n("addNewSectione0512f7") },
    { keys: "?", description: i18n("showThisShortcutsPanel838be9e") },
  ];
  return (
    <Dialog onClose={onClose} title={i18n("keyboardShortcutsb465751")} size="sm" variant="center">
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
    </Dialog>
  );
}
