"use client";

import { useTranslations } from "next-intl";
import { useMemo, useState, type ReactNode } from "react";

import { Dialog } from "@/components/ui/Dialog";

export type TagOption = { value: string; label: string; hint?: string; search?: string };
/** `open`: starts expanded (a single group always does). */
export type TagGroup = { key: string; label: string | null; items: TagOption[]; open?: boolean };

const normalize = (text: string) =>
  text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();

function FilterChip({ option, on, onToggle, groupLabel }: { option: TagOption; on: boolean; onToggle: () => void; groupLabel?: string | null }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      title={option.hint}
      onClick={onToggle}
      className="inline-flex min-h-9 items-center gap-1.5 rounded-full px-3.5 text-sm font-semibold"
      style={{
        background: on ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
        border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
        color: on ? "var(--text)" : "var(--text-soft)",
      }}
    >
      {on ? <span aria-hidden="true">✓</span> : null}
      {option.label}
      {groupLabel ? (
        <span className="text-xs font-normal" style={{ color: "var(--dim)" }}>
          · {groupLabel}
        </span>
      ) : null}
    </button>
  );
}

/**
 * The tag picker of board 3b Q2: a side panel on wide screens and a bottom
 * sheet on phones. Search on top, the picked ones first, suggestions from
 * the groups already in use, then collapsed groups with counts. Typing
 * flattens to matches. «Τέλος» applies; closing any other way discards.
 */
export function TagPicker({
  title,
  groups,
  selected,
  max,
  onDone,
  onClose,
  footer,
}: {
  title: string;
  groups: TagGroup[];
  selected: string[];
  max?: number;
  onDone: (values: string[]) => void;
  onClose: () => void;
  footer?: (query: string) => ReactNode;
}) {
  const t = useTranslations("AdminPublicPage");
  const [picked, setPicked] = useState<string[]>(selected);
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState<Set<string>>(
    () => new Set(groups.filter((group) => group.open || groups.length === 1).map((group) => group.key)),
  );

  const all = useMemo(() => groups.flatMap((group) => group.items.map((item) => ({ item, group }))), [groups]);
  const byValue = useMemo(() => new Map(all.map((entry) => [entry.item.value, entry])), [all]);
  const full = max !== undefined && picked.length >= max;
  const toggle = (value: string) =>
    setPicked((current) =>
      current.includes(value) ? current.filter((other) => other !== value) : full ? current : [...current, value],
    );

  const term = normalize(query.trim());
  const matches = term
    ? all.filter(({ item }) => normalize(`${item.label} ${item.search ?? ""}`).includes(term))
    : [];
  // Suggestions: what else sits in the groups already in use.
  const usedGroups = new Set(selected.map((value) => byValue.get(value)?.group.key));
  const suggestions =
    groups.length > 1
      ? all.filter(({ item, group }) => usedGroups.has(group.key) && !picked.includes(item.value)).slice(0, 6)
      : [];

  return (
    <Dialog
      onClose={onClose}
      title={title}
      variant="panel"
      size="lg"
      headerActions={
        max !== undefined ? (
          <span className="font-mono text-xs" style={{ color: full ? "var(--warning)" : "var(--dim)" }}>
            {picked.length}/{max}
          </span>
        ) : null
      }
      footer={
        <>
          <button
            type="button"
            onClick={onClose}
            className="min-h-11 rounded-full px-5 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="button"
            onClick={() => onDone(picked)}
            className="min-h-11 rounded-full px-6 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("done")}
          </button>
        </>
      }
    >
        <div className="sticky top-0 z-(--z-raised) -mx-5 px-5 pb-3 sm:-mx-6 sm:px-6" style={{ background: "var(--panel)" }}>
          <input
            data-autofocus
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("search")}
            aria-label={t("search")}
            className="w-full rounded-2xl px-4 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </div>

        <div>
          {term ? (
            <div className="flex flex-col gap-3">
              <div className="flex flex-wrap gap-2">
                {matches.map(({ item, group }) => (
                  <FilterChip
                    key={item.value}
                    option={item}
                    on={picked.includes(item.value)}
                    onToggle={() => toggle(item.value)}
                    groupLabel={group.label}
                  />
                ))}
              </div>
              {matches.length === 0 ? (
                <p className="text-sm" style={{ color: "var(--muted)" }}>
                  {t("noMatch")}
                </p>
              ) : null}
              {footer?.(query.trim())}
            </div>
          ) : (
            <div className="flex flex-col gap-5">
              {picked.length > 0 ? (
                <section className="flex flex-col gap-2">
                  <h3 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
                    {t("selected", { count: picked.length })}
                  </h3>
                  <div className="flex flex-wrap gap-2">
                    {picked.map((value) => {
                      const entry = byValue.get(value);
                      return entry ? <FilterChip key={value} option={entry.item} on onToggle={() => toggle(value)} /> : null;
                    })}
                  </div>
                </section>
              ) : null}
              {suggestions.length > 0 ? (
                <section className="flex flex-col gap-2">
                  <h3 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
                    {t("suggested")}
                  </h3>
                  <div className="flex flex-wrap gap-2">
                    {suggestions.map(({ item }) => (
                      <FilterChip key={item.value} option={item} on={false} onToggle={() => toggle(item.value)} />
                    ))}
                  </div>
                </section>
              ) : null}
              <div className="flex flex-col">
                {groups.map((group) => {
                  const count = group.items.filter((item) => picked.includes(item.value)).length;
                  const expanded = open.has(group.key);
                  return (
                    <section key={group.key} style={{ borderTop: group.label ? "1px solid var(--border)" : undefined }}>
                      {group.label ? (
                        <button
                          type="button"
                          aria-expanded={expanded}
                          onClick={() =>
                            setOpen((current) => {
                              const next = new Set(current);
                              if (next.has(group.key)) next.delete(group.key);
                              else next.add(group.key);
                              return next;
                            })
                          }
                          className="flex w-full items-center justify-between py-3 text-sm font-bold"
                          style={{ color: "var(--text)" }}
                        >
                          <span className="flex items-center gap-2">
                            {group.label}
                            {count > 0 ? (
                              <span
                                className="rounded-full px-2 text-xs"
                                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                              >
                                {count}
                              </span>
                            ) : null}
                          </span>
                          <span aria-hidden="true" style={{ color: "var(--dim)" }}>
                            {expanded ? "▾" : "▸"}
                          </span>
                        </button>
                      ) : null}
                      {expanded || !group.label ? (
                        <div className="flex flex-wrap gap-2 pb-3">
                          {group.items.map((item) => (
                            <FilterChip
                              key={item.value}
                              option={item}
                              on={picked.includes(item.value)}
                              onToggle={() => toggle(item.value)}
                            />
                          ))}
                        </div>
                      ) : null}
                    </section>
                  );
                })}
              </div>
              {footer?.("")}
            </div>
          )}
        </div>

    </Dialog>
  );
}
