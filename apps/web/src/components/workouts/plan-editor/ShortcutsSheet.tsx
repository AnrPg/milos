"use client";

import { useTranslations } from "next-intl";

import { Dialog } from "@/components/ui/Dialog";

import { SHEET, keyLabel } from "./keymap";

/** Every shortcut of the editor («?» or Mod+/). */
export function ShortcutsSheet({ mac, onClose }: { mac: boolean; onClose: () => void }) {
  const t = useTranslations("PlanEditor.sheet");
  return (
    <Dialog onClose={onClose} title={t("title")} size="lg" variant="sheet" testId="plan-shortcuts">
      <div className="flex flex-col gap-4">
        {SHEET.map(({ group, rows }) => (
          <section key={group}>
            <h4 className="mb-1.5 text-xs font-bold uppercase tracking-wide" style={{ color: "var(--muted)" }}>{t(group)}</h4>
            <dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
              {rows.map(([keys, what]) => (
                <div key={what} className="contents">
                  <dt style={{ color: "var(--text)" }}>{t(what)}</dt>
                  <dd>
                    <kbd className="rounded border px-1.5 font-mono text-xs" style={{ borderColor: "var(--border-strong)", color: "var(--text-soft)" }}>
                      {keys.startsWith("@") ? t(keys.slice(1)) : keyLabel(keys, mac)}
                    </kbd>
                  </dd>
                </div>
              ))}
            </dl>
          </section>
        ))}
      </div>
    </Dialog>
  );
}
