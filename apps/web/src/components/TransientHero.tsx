"use client";

import { useEffect, useState, type ReactNode } from "react";

type Props = {
  children: ReactNode;
  label?: string;
  timeoutMs?: number;
};

export function TransientHero({ children, label = "page introduction", timeoutMs = 3000 }: Props) {
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    if (!visible) return;

    const timeout = window.setTimeout(() => setVisible(false), timeoutMs);
    return () => window.clearTimeout(timeout);
  }, [timeoutMs, visible]);

  if (!visible) {
    return (
      <div className="flex justify-end">
        <button
          type="button"
          onClick={() => setVisible(true)}
          className="rounded-full px-3 py-1.5 text-[11px] font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--dim)" }}
          aria-label={`Show ${label}`}
        >
          Show intro
        </button>
      </div>
    );
  }

  return <div aria-label={label}>{children}</div>;
}
