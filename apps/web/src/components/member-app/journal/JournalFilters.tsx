"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import { EMPTY_JOURNAL_FILTER, type JournalFeedFilter, type JournalKind, type JournalVisibility } from "@/api/journal";
import { FilterChipRow, type FilterChip } from "@/components/filters/FilterChipRow";
import { ChoiceChips, FilterPage, FilterSection } from "@/components/filters/FilterPage";
import { useSourceDirectory } from "@/components/providers/use-providers";
import { JOURNAL_KINDS, JOURNAL_VISIBILITIES, journalFilterCount } from "@/lib/journal-filter";
import { sourceOptions } from "@/lib/provider-sources";

/**
 * Ροή's filters (board 17 Q3): «Φίλτρα (n)» first, then Πηγή, Τύπος and
 * Ορατότητα as chips; the page adds text search and dates. Every provider
 * (and the ones you left), freeform and devices are sources.
 */
export function JournalFilters({
  filter,
  onChange,
}: {
  filter: JournalFeedFilter;
  onChange: (filter: JournalFeedFilter) => void;
}) {
  const t = useTranslations("Providers");
  const tJournal = useTranslations("MemberApp.journal");
  const directory = useSourceDirectory();
  const [pageOpen, setPageOpen] = useState(false);
  const sources = sourceOptions(directory, {
    freeform: t("source.freeform"),
    device: t("source.device"),
    former: (name) => t("source.former", { name }),
  });
  const kinds = JOURNAL_KINDS.map((kind) => ({ value: kind, label: tJournal(`kind.${kind}`) }));
  const visibilities = JOURNAL_VISIBILITIES.map((rung) => ({ value: rung, label: tJournal(`visibility.${rung}`) }));
  const count = journalFilterCount(filter);
  const set = (patch: Partial<JournalFeedFilter>) => onChange({ ...filter, ...patch });

  const chips: FilterChip[] = [
    {
      key: "sources",
      kind: "menu",
      label: t("filter.source"),
      options: sources,
      selected: filter.sources,
      multiple: true,
      onChange: (values) => set({ sources: values }),
    },
    {
      key: "kinds",
      kind: "menu",
      label: t("filter.kind"),
      options: kinds,
      selected: filter.kinds,
      multiple: true,
      onChange: (values) => set({ kinds: values as JournalKind[] }),
    },
    {
      key: "visibilities",
      kind: "menu",
      label: t("filter.visibility"),
      options: visibilities,
      selected: filter.visibilities,
      multiple: true,
      onChange: (values) => set({ visibilities: values as JournalVisibility[] }),
    },
  ];

  return (
    <>
      <FilterChipRow
        ariaLabel={tJournal("filterLabel")}
        activeCount={count}
        onOpenFilters={() => setPageOpen(true)}
        onClear={() => onChange(EMPTY_JOURNAL_FILTER)}
        chips={chips}
        leading={
          filter.q ? (
            <button
              type="button"
              onClick={() => set({ q: null })}
              aria-label={t("filter.clearSearch", { q: filter.q })}
              className="flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 text-sm font-semibold"
              style={{ background: "color-mix(in srgb, var(--primary) 16%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
            >
              «{filter.q}» <span aria-hidden="true">✕</span>
            </button>
          ) : null
        }
      />
      {pageOpen ? (
        <FilterPage
          title={t("filter.title")}
          onClose={() => setPageOpen(false)}
          onClear={() => onChange(EMPTY_JOURNAL_FILTER)}
        >
          <FilterSection label={t("filter.search")}>
            <SearchField key={filter.q ?? ""} value={filter.q ?? ""} onCommit={(q) => set({ q: q || null })} label={t("filter.search")} placeholder={t("filter.searchPlaceholder")} />
          </FilterSection>
          <FilterSection label={t("filter.source")}>
            <ChoiceChips ariaLabel={t("filter.source")} options={sources} selected={filter.sources} multiple onChange={(values) => set({ sources: values })} />
          </FilterSection>
          <FilterSection label={t("filter.kind")}>
            <ChoiceChips ariaLabel={t("filter.kind")} options={kinds} selected={filter.kinds} multiple onChange={(values) => set({ kinds: values })} />
          </FilterSection>
          <FilterSection label={t("filter.visibility")}>
            <ChoiceChips
              ariaLabel={t("filter.visibility")}
              options={visibilities}
              selected={filter.visibilities}
              multiple
              onChange={(values) => set({ visibilities: values })}
            />
          </FilterSection>
          <FilterSection label={t("filter.dates")}>
            <div className="grid grid-cols-2 gap-3">
              <DateField label={t("filter.from")} value={filter.date_from} max={filter.date_to} onChange={(date_from) => set({ date_from })} />
              <DateField label={t("filter.to")} value={filter.date_to} min={filter.date_from} onChange={(date_to) => set({ date_to })} />
            </div>
          </FilterSection>
        </FilterPage>
      ) : null}
    </>
  );
}

/** Commits the text 400 ms after typing stops, so the feed is not asked on every key. */
function SearchField({
  value,
  onCommit,
  label,
  placeholder,
}: {
  value: string;
  onCommit: (value: string) => void;
  label: string;
  placeholder: string;
}) {
  const [draft, setDraft] = useState(value);
  useEffect(() => {
    const text = draft.trim();
    if (text === value || (text.length > 0 && text.length < 2)) return;
    const timer = window.setTimeout(() => onCommit(text.slice(0, 100)), 400);
    return () => window.clearTimeout(timer);
  }, [draft, value, onCommit]);
  return (
    <input
      type="search"
      aria-label={label}
      placeholder={placeholder}
      value={draft}
      maxLength={100}
      onChange={(event) => setDraft(event.target.value)}
      className="min-h-11 w-full rounded-2xl px-4 text-sm outline-none"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
    />
  );
}

function DateField({
  label,
  value,
  min,
  max,
  onChange,
}: {
  label: string;
  value: string | null;
  min?: string | null;
  max?: string | null;
  onChange: (value: string | null) => void;
}) {
  return (
    <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
      {label}
      <input
        type="date"
        value={value ?? ""}
        min={min ?? undefined}
        max={max ?? undefined}
        onChange={(event) => onChange(event.target.value || null)}
        className="min-h-11 rounded-2xl px-3 text-sm outline-none"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
    </label>
  );
}
