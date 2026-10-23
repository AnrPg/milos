"use client";

import { useId, useState } from "react";
import { useTranslations } from "next-intl";

import type { FacilityLocation } from "@/api/facility";
import { coversLocation, type LocationScope } from "@/lib/location-scope";

/** Above this many branches the picker gets a search field. */
const SEARCH_FROM = 8;

/**
 * «Όλα τα καταστήματα» or a set of branches (ADR-186). Offers only what the
 * signed-in person may hand out: every branch when they work everywhere,
 * otherwise their own branches.
 */
export function BranchScopePicker({
  locations,
  value,
  onChange,
  allowed = "all",
  disabled = false,
  legend,
  help,
}: {
  locations: FacilityLocation[];
  value: LocationScope;
  onChange: (scope: LocationScope) => void;
  allowed?: LocationScope;
  disabled?: boolean;
  legend?: string;
  help?: string;
}) {
  const t = useTranslations("BranchScope");
  const searchId = useId();
  const [query, setQuery] = useState("");
  const offered = locations.filter((location) => !location.archived_at && coversLocation(allowed, location.id));
  const needle = query.trim().toLocaleLowerCase();
  const shown = needle
    ? offered.filter((location) => location.name.toLocaleLowerCase().includes(needle))
    : offered;
  const selected = value === "all" ? [] : value;

  const toggle = (id: string) => {
    if (value === "all") return onChange([id]);
    onChange(selected.includes(id) ? selected.filter((item) => item !== id) : [...selected, id].sort());
  };

  const chipStyle = (on: boolean) => ({
    background: on ? "var(--primary)" : "var(--panel-muted)",
    border: "1px solid var(--border)",
    color: on ? "var(--primary-contrast)" : "var(--text-soft)",
  });

  return (
    <fieldset disabled={disabled}>
      <legend className="block text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>
        {legend ?? t("branches")}
      </legend>
      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{help ?? t("branchesHelp")}</p>
      {offered.length > SEARCH_FROM ? (
        <>
          <label htmlFor={searchId} className="sr-only">{t("searchBranches")}</label>
          <input
            id={searchId}
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("searchBranches")}
            className="mt-2 w-full rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--control-bg)", border: "1px solid var(--control-border)", color: "var(--text)" }}
          />
        </>
      ) : null}
      <div className="mt-2 flex max-h-64 flex-wrap gap-2 overflow-y-auto">
        {allowed === "all" ? (
          <button
            type="button"
            aria-pressed={value === "all"}
            onClick={() => onChange("all")}
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
            style={chipStyle(value === "all")}
          >
            {t("allBranches")}
          </button>
        ) : null}
        {shown.map((location) => {
          const on = selected.includes(location.id);
          return (
            <button
              key={location.id}
              type="button"
              aria-pressed={on}
              onClick={() => toggle(location.id)}
              className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
              style={chipStyle(on)}
            >
              {location.name}
            </button>
          );
        })}
        {needle && shown.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("noBranchMatches")}</p>
        ) : null}
      </div>
      {value !== "all" && value.length === 0 ? (
        <p className="mt-2 text-xs" style={{ color: "var(--danger)" }}>{t("chooseOneBranch")}</p>
      ) : null}
    </fieldset>
  );
}
