"use client";

import { useId, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { listAdminLocations, type FacilityLocation } from "@/api/facility";
import { Popover } from "@/components/ui/Popover";
import { useSession } from "@/components/session-provider";

/** Above this many branches the checklist gets a search field. */
const SEARCH_FROM = 8;
const STORAGE_PREFIX = "palee.branchFilter.";

export type BranchFilterState = {
  /** The active branches the signed-in staff member sees (the API narrows them to their scope). */
  locations: FacilityLocation[];
  /** The chosen branches; [] means «Όλα». */
  selected: string[];
  setSelected: (ids: string[]) => void;
  /** The `location_ids` query value, or undefined for «Όλα». */
  param: string | undefined;
  /** The filter shows only to people who see at least two active branches. */
  visible: boolean;
};

function readStored(pageKey: string): string[] {
  try {
    const raw = window.localStorage.getItem(STORAGE_PREFIX + pageKey);
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : [];
  } catch {
    return [];
  }
}

function writeStored(pageKey: string, ids: string[]) {
  try {
    if (ids.length === 0) window.localStorage.removeItem(STORAGE_PREFIX + pageKey);
    else window.localStorage.setItem(STORAGE_PREFIX + pageKey, JSON.stringify(ids));
  } catch {
    // Storage blocked: the filter still works for this visit.
  }
}

/**
 * The page branch filter of the finance, coaching and statistics pages
 * (ADR-186 §7), remembered per page in this browser. A remembered branch that
 * is no longer offered is ignored.
 */
export function useBranchFilter(pageKey: string): BranchFilterState {
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const locationsQuery = useQuery({
    queryKey: ["admin", "locations"],
    enabled: Boolean(token),
    queryFn: () => listAdminLocations(token!),
  });
  const locations = (locationsQuery.data ?? []).filter((location) => !location.archived_at);
  const [chosen, setChosen] = useState<string[] | null>(null);
  const known = new Set(locations.map((location) => location.id));
  const stored = chosen ?? (typeof window === "undefined" ? [] : readStored(pageKey));
  const selected = stored.filter((id) => known.has(id)).sort();
  const visible = locations.length >= 2;

  const setSelected = (ids: string[]) => {
    const next = Array.from(new Set(ids)).sort();
    setChosen(next);
    writeStored(pageKey, next);
  };

  return {
    locations,
    selected: visible ? selected : [],
    setSelected,
    param: visible && selected.length > 0 ? selected.join(",") : undefined,
    visible,
  };
}

/** «Καταστήματα: Όλα ▾»: a themed checklist of branches in a popover. */
export function BranchFilterControl({ filter }: { filter: BranchFilterState }) {
  const t = useTranslations("BranchScope");
  const anchorRef = useRef<HTMLButtonElement>(null);
  const menuId = useId();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  if (!filter.visible) return null;

  const { locations, selected, setSelected } = filter;
  const names = locations.filter((location) => selected.includes(location.id)).map((location) => location.name);
  const label =
    selected.length === 0
      ? t("filterAll")
      : selected.length === 1
        ? names[0]
        : t("filterCount", { count: selected.length });
  const needle = query.trim().toLocaleLowerCase();
  const shown = needle ? locations.filter((location) => location.name.toLocaleLowerCase().includes(needle)) : locations;

  const toggle = (id: string) =>
    setSelected(selected.includes(id) ? selected.filter((item) => item !== id) : [...selected, id]);

  const rowStyle = (on: boolean) => ({
    background: on ? "var(--panel-muted)" : "transparent",
    color: "var(--text)",
  });

  const box = (on: boolean) => (
    <span
      aria-hidden
      className="inline-flex h-4 w-4 shrink-0 items-center justify-center rounded text-[10px] font-bold"
      style={{
        background: on ? "var(--primary)" : "var(--control-bg)",
        border: "1px solid var(--control-border)",
        color: "var(--primary-contrast)",
      }}
    >
      {on ? "✓" : ""}
    </span>
  );

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        onClick={() => setOpen((value) => !value)}
        className="inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      >
        <span style={{ color: "var(--muted)" }}>{t("filterLabel")}</span>
        <span style={{ color: "var(--text)" }}>{label}</span>
        <span aria-hidden>▾</span>
      </button>
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={() => setOpen(false)}
        role="menu"
        id={menuId}
        ariaLabel={t("filterLabel")}
        minWidth={240}
        className="rounded-2xl p-2 shadow-lg"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", maxHeight: 360 }}
      >
        {locations.length > SEARCH_FROM ? (
          <input
            type="search"
            aria-label={t("searchBranches")}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("searchBranches")}
            className="mb-2 w-full rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--control-bg)", border: "1px solid var(--control-border)", color: "var(--text)" }}
          />
        ) : null}
        <button
          type="button"
          role="menuitemcheckbox"
          aria-checked={selected.length === 0}
          onClick={() => setSelected([])}
          className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-left text-sm font-semibold"
          style={rowStyle(selected.length === 0)}
        >
          {box(selected.length === 0)}
          {t("allBranches")}
        </button>
        {shown.map((location) => {
          const on = selected.includes(location.id);
          return (
            <button
              key={location.id}
              type="button"
              role="menuitemcheckbox"
              aria-checked={on}
              onClick={() => toggle(location.id)}
              className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-left text-sm"
              style={rowStyle(on)}
            >
              {box(on)}
              {location.name}
            </button>
          );
        })}
        {needle && shown.length === 0 ? (
          <p className="px-3 py-2 text-sm" style={{ color: "var(--muted)" }}>{t("noBranchMatches")}</p>
        ) : null}
      </Popover>
    </>
  );
}

export type BranchSplit = { location_id: string; name: string; people?: number } & Record<string, unknown>;

/**
 * The per-branch rows a report returns when two or more branches are shown.
 * `columns` names the figures and formats them.
 */
export function BranchSplits({
  rows,
  columns,
}: {
  rows: BranchSplit[] | null | undefined;
  columns: Array<{ key: string; label: string; format?: (value: unknown) => string }>;
}) {
  const t = useTranslations("BranchScope");
  if (!rows || rows.length < 2) return null;

  return (
    <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{t("perBranch")}</p>
      <div className="mt-3 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr style={{ color: "var(--muted)" }}>
              <th className="py-2 pr-4 text-left font-semibold">{t("branch")}</th>
              {columns.map((column) => (
                <th key={column.key} className="py-2 pr-4 text-right font-semibold">{column.label}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.location_id} style={{ borderTop: "1px solid var(--border)", color: "var(--text)" }}>
                <td className="py-2 pr-4">{row.name}</td>
                {columns.map((column) => (
                  <td key={column.key} className="py-2 pr-4 text-right tabular-nums">
                    {column.format ? column.format(row[column.key]) : String(row[column.key] ?? 0)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("perBranchHelp")}</p>
    </section>
  );
}
