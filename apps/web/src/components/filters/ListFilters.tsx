"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { FilterChipRow, type ChipOption, type FilterChip } from "./FilterChipRow";
import { ChoiceChips, FilterPage, FilterSection } from "./FilterPage";
import { emptyListFilter, listFilterCount, type ListFilter, type ListFilterShape } from "./list-filter";

/** One filter of a list screen: what it is called and what it offers. */
export type ListFilterField<S extends ListFilterShape> = {
  key: keyof S & string;
  label: string;
  /** In the chip row as well as in the sheet (default); false keeps it in the sheet only. */
  chip?: boolean;
  /** «one»/«many» fields: the choices; a field with fewer than two is not shown (nothing to choose). */
  options?: ChipOption[];
  /** A toggle's heading in the sheet («Συντάκτης» over «Όλα · Μόνο coaches»); its label by default. */
  section?: string;
};

const ALL = "__all";

/**
 * The chip row + «Φίλτρα (n)» sheet of a list screen (vision §7.2, §8.5),
 * from a declared `ListFilter` shape: menus for «one»/«many» fields, on/off
 * chips for toggles, and the same fields as sections of the sheet. The row
 * never scrolls sideways (`fit`). Nothing renders when there is nothing to
 * choose, so a short list has no empty filters.
 */
export function ListFilters<S extends ListFilterShape>({
  shape,
  fields,
  filter,
  onChange,
  title,
  resultCount,
}: {
  shape: S;
  fields: ListFilterField<S>[];
  filter: ListFilter<S>;
  onChange: (filter: ListFilter<S>) => void;
  /** The sheet's title and the row's accessible name. */
  title: string;
  /** For «Δείξε N»; left out for paged lists. */
  resultCount?: number;
}) {
  const t = useTranslations("Filters");
  const [open, setOpen] = useState(false);
  const values = filter as Record<string, string[] | boolean>;
  const set = (key: string, value: string[] | boolean) => onChange({ ...filter, [key]: value });
  const clear = () => onChange(emptyListFilter(shape));

  const shown = fields.filter((field) => {
    if (shape[field.key] === "toggle") return true;
    const value = values[field.key] as string[];
    return (field.options?.length ?? 0) > 1 || value.length > 0;
  });
  if (shown.length === 0) return null;

  const chips: FilterChip[] = shown
    .filter((field) => field.chip !== false)
    .map((field) => {
      const value = values[field.key];
      if (shape[field.key] === "toggle") {
        return { key: field.key, kind: "toggle", label: field.label, active: value === true, onToggle: () => set(field.key, !value) };
      }
      return {
        key: field.key,
        kind: "menu",
        label: field.label,
        options: field.options ?? [],
        selected: value as string[],
        multiple: shape[field.key] === "many",
        onChange: (next: string[]) => set(field.key, next),
      };
    });

  return (
    <>
      <FilterChipRow
        fit
        ariaLabel={title}
        activeCount={listFilterCount(values)}
        onOpenFilters={() => setOpen(true)}
        onClear={clear}
        chips={chips}
      />
      {open ? (
        <FilterPage title={title} resultCount={resultCount} onClose={() => setOpen(false)} onClear={clear}>
          {shown.map((field) => {
            const kind = shape[field.key];
            const value = values[field.key];
            return (
              <FilterSection key={field.key} label={field.section ?? field.label}>
                {kind === "toggle" ? (
                  <ChoiceChips
                    ariaLabel={field.label}
                    multiple={false}
                    options={[
                      { value: ALL, label: t("all") },
                      { value: field.key, label: field.label },
                    ]}
                    selected={[value === true ? field.key : ALL]}
                    onChange={([next]) => set(field.key, next === field.key)}
                  />
                ) : kind === "one" ? (
                  <ChoiceChips
                    ariaLabel={field.label}
                    multiple={false}
                    options={[{ value: ALL, label: t("all") }, ...(field.options ?? [])]}
                    selected={(value as string[]).length > 0 ? (value as string[]) : [ALL]}
                    onChange={([next]) => set(field.key, next === ALL ? [] : [next])}
                  />
                ) : (
                  <ChoiceChips
                    ariaLabel={field.label}
                    multiple
                    options={field.options ?? []}
                    selected={value as string[]}
                    onChange={(next) => set(field.key, next)}
                  />
                )}
              </FilterSection>
            );
          })}
        </FilterPage>
      ) : null}
    </>
  );
}
