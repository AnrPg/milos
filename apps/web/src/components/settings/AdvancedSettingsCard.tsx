"use client";

import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

// ADR-255 (mockup s10 A): one «Προχωρημένα» card at the end of Ρυθμίσεις.
// Closed by default; open, it lists the settings with a good default in
// groups, and a search box narrows the groups by word.

export type AdvancedGroup = {
  id: string;
  title: string;
  /** Words the search matches besides the title. */
  keywords?: string[];
  content: ReactNode;
};

const fold = (value: string) =>
  value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase();

/** Pure: the groups whose title or keywords contain the query. */
export function matchingGroups<G extends { title: string; keywords?: string[] }>(groups: G[], query: string): G[] {
  const needle = fold(query.trim());
  if (!needle) return groups;
  return groups.filter((group) => [group.title, ...(group.keywords ?? [])].some((word) => fold(word).includes(needle)));
}

export function AdvancedSettingsCard({ count, groups }: { count: number; groups: AdvancedGroup[] }) {
  const t = useTranslations("AdvancedSettings");
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const id = useId();
  const shown = matchingGroups(groups, query);

  return (
    <section
      id="advanced"
      className="rounded-[2.2rem] p-6"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="advanced-settings"
    >
      <button
        type="button"
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-3 text-start"
      >
        <span className="min-w-0">
          <b className="block text-base" style={{ color: "var(--text)" }}>{t("title")}</b>
          <span className="block text-sm" style={{ color: "var(--muted)" }}>
            {count ? t("hintCount", { count }) : t("hint")}
          </span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--muted)" }}>{open ? "▴" : "▾"}</span>
      </button>
      {open ? (
        <div id={id} className="mt-5 space-y-6">
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            aria-label={t("search")}
            placeholder={t("search")}
            className="min-h-10 w-full rounded-full px-4 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            data-testid="advanced-settings-search"
          />
          {shown.length === 0 ? (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("noMatch")}</p>
          ) : (
            shown.map((group) => (
              <div key={group.id} className="space-y-3" data-testid={`advanced-group-${group.id}`}>
                <h3
                  className="text-xs font-bold uppercase tracking-[0.1em]"
                  style={{ color: "var(--muted)" }}
                >
                  {group.title}
                </h3>
                <div className="space-y-4">{group.content}</div>
              </div>
            ))
          )}
        </div>
      ) : null}
    </section>
  );
}
