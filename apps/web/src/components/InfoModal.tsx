"use client";

import {useUiTranslations} from "@/i18n/ui";
import { Dialog } from "@/components/ui/Dialog";

type InfoModalProps = {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
};

export function InfoModal({ title, onClose, children }: InfoModalProps) {
  return (
    <Dialog onClose={onClose} title={title} size="md" variant="center">
      <div className="space-y-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
        {children}
      </div>
    </Dialog>
  );
}

type HelpIconProps = {
  tooltip: string;
  onClick: () => void;
};

export function HelpIcon({ tooltip, onClick }: HelpIconProps) {
  const i18n = useUiTranslations();
  return (
    <button
      className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold transition-colors hover:opacity-80"
      style={{ background: "var(--border)", color: "var(--dim)", border: "1px solid var(--border-strong)" }}
      title={tooltip}
      onClick={onClick}
      type="button"
      aria-label={i18n("info3d071a5") + (tooltip)}
    >
      ?
    </button>
  );
}
