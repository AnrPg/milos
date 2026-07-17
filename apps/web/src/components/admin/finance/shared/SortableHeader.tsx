"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { ColumnKey, SortState } from "@/components/admin/finance/hooks/useSortFilter";
import { AnchoredOverlay } from "./AnchoredOverlay";

interface Props {
  column: ColumnKey;
  label: string;
  sort: SortState;
  hasFilter: boolean;
  onSort: () => void;
  filterSlot: ReactNode;
}

export function SortableHeader({ column, label, sort, hasFilter, onSort, filterSlot }: Props) {
  const i18n = useUiTranslations();
  const [filterOpen, setFilterOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const isActive = sort.column === column;

  useEffect(() => {
    if (!filterOpen) return;

    function handleClick(e: MouseEvent) {
      const target = e.target as Node;
      if (!ref.current?.contains(target) && !overlayRef.current?.contains(target)) setFilterOpen(false);
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
      className="px-4 py-3 text-start text-xs font-semibold uppercase tracking-[0.18em]"
      style={{ color: "var(--dim)", background: "var(--panel)", whiteSpace: "nowrap" }}
    >
      <div ref={ref} className="group relative flex items-center gap-1">
        <button
          type="button"
          onClick={onSort}
          className="flex items-center gap-1 hover:text-[var(--text-soft)] transition-colors"
          style={{ color: isActive ? "var(--text-soft)" : undefined }}
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
            color: hasFilter ? "var(--primary)" : "var(--dim)",
            opacity: hasFilter ? 1 : undefined,
          }}
          title={i18n("filterd7decf1")}
        >
          <span
            className={hasFilter ? "opacity-100" : "opacity-0 group-hover:opacity-60"}
            style={{ fontSize: "10px" }}
          >
            ▾
          </span>
        </button>

        {filterOpen && (
          <AnchoredOverlay
            anchorRef={ref}
            overlayRef={overlayRef}
            minWidth={220}
            className="rounded-xl p-3 shadow-xl"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)" }}
          >
            {filterSlot}
          </AnchoredOverlay>
        )}
      </div>
    </th>
  );
}
