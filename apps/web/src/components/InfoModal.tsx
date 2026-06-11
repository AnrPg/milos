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
        style={{ background: "#111118", border: "1px solid #1a1a28" }}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-bold" style={{ color: "#F0EDF8" }}>{title}</h2>
          <button
            className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold"
            style={{ background: "#1a1a28", color: "#8888aa" }}
            onClick={onClose}
            type="button"
          >
            Close
          </button>
        </div>
        <div className="mt-4 space-y-3 text-sm leading-6" style={{ color: "#8888aa" }}>
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
      style={{ background: "#1a1a28", color: "#55556a", border: "1px solid #2a2a3a" }}
      title={tooltip}
      onClick={onClick}
      type="button"
      aria-label={`Info: ${tooltip}`}
    >
      ?
    </button>
  );
}
