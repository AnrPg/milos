"use client";

import { useEffect, useRef, useState } from "react";
import type { FinanceRecord } from "@/api/finance";

interface Props {
  userId: string;
  currentCode: string | null;
  packages: FinanceRecord[];
  pending: boolean;
  onAssign: (packageId: string) => void;
}

export function InlineAssignPackage({ currentCode, packages, pending, onAssign }: Props) {
  const [open, setOpen] = useState(false);
  const [selectedId, setSelectedId] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }

    document.addEventListener("mousedown", handleClick);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handleClick);
      document.removeEventListener("keydown", handleKey);
    };
  }, [open]);

  function handleAssign() {
    if (!selectedId) return;
    onAssign(selectedId);
    setOpen(false);
    setSelectedId("");
  }

  return (
    <div ref={ref} className="relative inline-block">
      {currentCode ? (
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="group flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold transition-opacity hover:opacity-70"
          style={{ background: "#1a1a28", color: "#c0c0d8" }}
          title="Change package"
        >
          {currentCode}
          <span className="opacity-0 group-hover:opacity-60 transition-opacity text-[10px]">✎</span>
        </button>
      ) : (
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="rounded-full px-3 py-1 text-xs font-semibold transition-opacity hover:opacity-80"
          style={{
            border: "1px solid rgba(217,93,57,0.35)",
            color: "#55556a",
            background: "transparent",
          }}
        >
          + Assign
        </button>
      )}

      {open && (
        <div
          className="absolute left-0 top-full z-50 mt-1 min-w-[180px] rounded-xl p-3 shadow-xl"
          style={{ background: "#18181f", border: "1px solid #2a2a3a" }}
        >
          <select
            value={selectedId}
            onChange={(e) => setSelectedId(e.target.value)}
            className="w-full rounded-lg px-2 py-1.5 text-xs mb-2"
            style={{ background: "#111118", color: "#c0c0d8", border: "1px solid #2a2a3a" }}
          >
            <option value="">Select package…</option>
            {packages.map((pkg) => (
              <option key={String(pkg.id)} value={String(pkg.id)}>
                {String(pkg.code)}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={handleAssign}
            disabled={!selectedId || pending}
            className="w-full rounded-lg px-3 py-1.5 text-xs font-semibold transition-opacity disabled:opacity-40"
            style={{ background: "#d95d39", color: "#fff" }}
          >
            Assign
          </button>
        </div>
      )}
    </div>
  );
}
