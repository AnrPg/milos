"use client";

import { useEffect, useRef } from "react";

type InfoModalProps = {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
};

export function InfoModal({ title, onClose, children }: InfoModalProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    ref.current?.focus();
  }, []);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.65)" }}
      onClick={onClose}
      role="presentation"
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        className="w-full max-w-md rounded-[2rem] p-6 outline-none"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>{title}</h2>
          <button
            className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold"
            style={{ background: "var(--border)", color: "var(--muted)" }}
            onClick={onClose}
            type="button"
          >
            Close
          </button>
        </div>
        <div className="mt-4 space-y-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
          {children}
        </div>
      </div>
    </div>
  );
}

type HelpIconProps = {
  tooltip: string;
  onClick: () => void;
};

export function HelpIcon({ tooltip, onClick }: HelpIconProps) {
  return (
    <button
      className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold transition-colors hover:opacity-80"
      style={{ background: "var(--border)", color: "var(--dim)", border: "1px solid var(--border-strong)" }}
      title={tooltip}
      onClick={onClick}
      type="button"
      aria-label={`Info: ${tooltip}`}
    >
      ?
    </button>
  );
}
