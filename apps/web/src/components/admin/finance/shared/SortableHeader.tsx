"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import type { ColumnKey, SortState } from "@/components/admin/finance/hooks/useSortFilter";

interface Props {
  column: ColumnKey;
  label: string;
  sort: SortState;
  hasFilter: boolean;
  onSort: () => void;
  filterSlot: ReactNode;
}

export function SortableHeader({ column, label, sort, hasFilter, onSort, filterSlot }: Props) {
  const [filterOpen, setFilterOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const isActive = sort.column === column;

  useEffect(() => {
    if (!filterOpen) return;

    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setFilterOpen(false);
    }
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setFilterOpen(false);
    }

    document.addEventListener("mousedown", handleClick);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handleClick);
      document.removeEventListener("keydown", handleKey);
    };
  }, [filterOpen]);

  return (
    <th
      className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-[0.18em]"
      style={{ color: "#55556a", background: "#111118", whiteSpace: "nowrap" }}
    >
      <div ref={ref} className="group relative flex items-center gap-1">
        <button
          type="button"
          onClick={onSort}
          className="flex items-center gap-1 hover:text-[#c0c0d8] transition-colors"
          style={{ color: isActive ? "#c0c0d8" : undefined }}
        >
          {label}
          <span className="w-3 inline-block text-center">
            {isActive ? (sort.direction === "asc" ? "↑" : "↓") : ""}
          </span>
        </button>

        <button
          type="button"
          onClick={() => setFilterOpen((v) => !v)}
          className="transition-opacity"
          style={{
            color: hasFilter ? "#d95d39" : "#55556a",
            opacity: hasFilter ? 1 : undefined,
          }}
          title="Filter"
        >
          <span
            className={hasFilter ? "opacity-100" : "opacity-0 group-hover:opacity-60"}
            style={{ fontSize: "10px" }}
          >
            ▾
          </span>
        </button>

        {filterOpen && (
          <div
            className="absolute left-0 top-full z-50 mt-1 min-w-[200px] rounded-xl p-3 shadow-xl"
            style={{ background: "#18181f", border: "1px solid #2a2a3a" }}
          >
            {filterSlot}
          </div>
        )}
      </div>
    </th>
  );
}
