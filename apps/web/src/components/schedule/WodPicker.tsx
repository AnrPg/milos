"use client";

import { useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type KeyboardEvent } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { WorkoutRecord } from "@/api/workouts";
import { resolveWorkoutIcon } from "@/components/workouts/library/library-folders";
import { Dialog } from "@/components/ui/Dialog";
import { Popover } from "@/components/ui/Popover";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { SPARK_CREATE_STYLE } from "@/lib/spark";

/**
 * The class form's WOD field (ADR-176: optional). A gym's library outgrows a
 * dropdown fast, so the field opens a searchable list, newest first: a
 * popover under the field on wider screens, a bottom sheet on phones. "No WOD
 * yet" is a real choice, and "+ New WOD" sits on the field's label row so a
 * coach can write one instead of picking.
 */

const SMALL_SCREEN = "(max-width: 639px)";

const smallScreenQuery = () => (typeof window.matchMedia === "function" ? window.matchMedia(SMALL_SCREEN) : null);

function subscribeSmallScreen(onChange: () => void) {
  const query = smallScreenQuery();
  if (!query) return () => undefined;
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

function useSmallScreen() {
  return useSyncExternalStore(
    subscribeSmallScreen,
    () => smallScreenQuery()?.matches ?? false,
    () => false,
  );
}

/** Lower-case and without accents, so "τάμπατα" finds "Ταμπάτα". */
export function searchText(text: string) {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
}

/** The library newest first, narrowed by every word of the query (title or type). */
export function filterWorkouts(workouts: WorkoutRecord[], query: string, typeLabel: (type: string) => string) {
  const words = searchText(query).split(/\s+/).filter(Boolean);
  const stamp = (workout: WorkoutRecord) => workout.updated_at ?? workout.inserted_at ?? "";
  return workouts
    .filter((workout) => {
      if (words.length === 0) return true;
      const haystack = searchText(`${workout.title} ${typeLabel(workout.type)}`);
      return words.every((word) => haystack.includes(word));
    })
    .sort((a, b) => stamp(b).localeCompare(stamp(a)));
}

type Option = { id: string | null; workout: WorkoutRecord | null };

export function WodPicker({
  label,
  workouts,
  value,
  onChange,
  onCreateNew,
  noneHint,
}: {
  label: string;
  workouts: WorkoutRecord[];
  value: string | null;
  onChange: (workoutId: string | null) => void;
  /** Leaves the form for the WOD editor; the form comes back with the new WOD. */
  onCreateNew: () => void;
  /** What "No WOD yet" means here (a class, or each class of a series). */
  noneHint?: string;
}) {
  const t = useTranslations("Schedule");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const small = useSmallScreen();
  const id = useId();
  const labelId = `${id}-label`;
  const listId = `${id}-list`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [popoverWidth, setPopoverWidth] = useState(360);

  const typeLabel = (type: string) => semanticLabel(type, i18n);
  const selected = value ? workouts.find((workout) => workout.id === value) ?? null : null;
  const matches = useMemo(() => filterWorkouts(workouts, query, (type) => semanticLabel(type, i18n)), [workouts, query, i18n]);
  const options: Option[] = query.trim()
    ? matches.map((workout) => ({ id: workout.id, workout }))
    : [{ id: null, workout: null }, ...matches.map((workout) => ({ id: workout.id, workout }))];
  // Type to search straight away with a keyboard; on a phone the list comes
  // first and the search field waits for a tap, so the keyboard doesn't cover it.
  useEffect(() => {
    if (!open || small) return;
    const frame = window.requestAnimationFrame(() => searchRef.current?.focus());
    return () => window.cancelAnimationFrame(frame);
  }, [open, small]);
  const dateFormat = useMemo(() => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" }), [locale]);

  function openPicker() {
    setQuery("");
    const current = value ? 1 + filterWorkouts(workouts, "", typeLabel).findIndex((workout) => workout.id === value) : 0;
    setActive(Math.max(0, current));
    setPopoverWidth(Math.max(360, triggerRef.current?.offsetWidth ?? 0));
    setOpen(true);
  }

  function close() {
    setOpen(false);
    triggerRef.current?.focus();
  }

  function choose(option: Option) {
    onChange(option.id);
    close();
  }

  function onSearchKey(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      setActive((current) => Math.min(options.length - 1, Math.max(0, current + step)));
    } else if (event.key === "Home" && options.length) {
      setActive(0);
    } else if (event.key === "End" && options.length) {
      setActive(options.length - 1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const option = options[active];
      if (option) choose(option);
    }
  }

  const optionId = (index: number) => `${id}-option-${index}`;

  const body = (
    <div className="flex min-h-0 flex-col">
      <div className="shrink-0 p-3" style={{ borderBottom: "1px solid var(--border)" }}>
        <input
          ref={searchRef}
          type="text"
          inputMode="search"
          enterKeyHint="search"
          role="combobox"
          aria-expanded="true"
          aria-controls={listId}
          aria-activedescendant={options[active] ? optionId(active) : undefined}
          aria-label={t("wodPickerSearch")}
          className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          placeholder={t("wodPickerSearch")}
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
            setActive(0);
          }}
          onKeyDown={onSearchKey}
        />
      </div>
      <ul id={listId} role="listbox" aria-labelledby={labelId} tabIndex={-1} data-autofocus={small ? "" : undefined} className="min-h-0 flex-1 outline-none overflow-y-auto overscroll-contain p-1.5">
        {options.map((option, index) => {
          const isSelected = option.id === value;
          const isActive = index === active;
          return (
            <li
              key={option.id ?? "none"}
              id={optionId(index)}
              role="option"
              aria-selected={isSelected}
              className="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2.5"
              style={{ background: isActive ? "var(--panel-muted)" : "transparent" }}
              onMouseEnter={() => setActive(index)}
              onClick={() => choose(option)}
            >
              <span aria-hidden="true" className="w-6 shrink-0 text-center text-lg">
                {option.workout ? resolveWorkoutIcon(option.workout) : "○"}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {option.workout ? option.workout.title : t("wodPickerNone")}
                </span>
                <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>
                  {option.workout
                    ? [typeLabel(option.workout.type), stampLabel(option.workout, dateFormat)].filter(Boolean).join(" · ")
                    : noneHint ?? t("wodPickerNoneHint")}
                </span>
              </span>
              {isSelected ? (
                <span aria-hidden="true" className="shrink-0 text-sm font-bold" style={{ color: "var(--primary)" }}>
                  ✓
                </span>
              ) : null}
            </li>
          );
        })}
      </ul>
      {query.trim() && matches.length === 0 ? (
        <div className="space-y-3 px-4 pb-4 pt-1 text-sm" style={{ color: "var(--muted)" }}>
          <p>{t("wodPickerNoMatch", { query: query.trim() })}</p>
          <button
            type="button"
            className="rounded-full px-3 py-1.5 text-xs font-semibold"
            style={SPARK_CREATE_STYLE}
            onClick={onCreateNew}
          >
            + {t("wodPickerNew")}
          </button>
        </div>
      ) : null}
    </div>
  );

  return (
    <div className="space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
      <div className="flex items-center justify-between gap-2">
        <span id={labelId}>{label}</span>
        <button
          type="button"
          className="rounded-full px-2.5 py-0.5 text-xs font-semibold"
          style={SPARK_CREATE_STYLE}
          onClick={onCreateNew}
        >
          + {t("wodPickerNew")}
        </button>
      </div>
      <div className="relative">
        <button
          ref={triggerRef}
          type="button"
          aria-haspopup="dialog"
          aria-expanded={open}
          aria-labelledby={`${labelId} ${id}-value`}
          className="flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-start outline-none"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)", paddingInlineEnd: selected || value ? "4.5rem" : undefined }}
          onClick={() => (open ? close() : openPicker())}
        >
          <span aria-hidden="true" className="w-6 shrink-0 text-center text-lg">
            {selected ? resolveWorkoutIcon(selected) : "○"}
          </span>
          <span id={`${id}-value`} className="min-w-0 flex-1">
            <span className="block truncate font-semibold" style={{ color: value ? "var(--text)" : "var(--muted)" }}>
              {selected ? selected.title : value ? t("wodPickerChosen") : t("wodPickerNone")}
            </span>
            {selected ? (
              <span className="block truncate text-xs font-normal" style={{ color: "var(--muted)" }}>
                {typeLabel(selected.type)}
              </span>
            ) : null}
          </span>
          {value ? null : (
            <span aria-hidden="true" className="shrink-0" style={{ color: "var(--muted)" }}>
              ▾
            </span>
          )}
        </button>
        {value ? (
          <button
            type="button"
            aria-label={t("wodPickerClear")}
            className="absolute end-2 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full text-base"
            style={{ color: "var(--muted)" }}
            onClick={() => onChange(null)}
          >
            ×
          </button>
        ) : null}
      </div>

      {open && small ? (
        <Dialog onClose={close} title={label} size="md" variant="sheet" plainBody panelClassName="h-[80dvh]">
          {body}
        </Dialog>
      ) : null}
      <Popover
        anchorRef={triggerRef}
        open={open && !small}
        onClose={() => setOpen(false)}
        role="dialog"
        ariaLabel={label}
        width={popoverWidth}
        className="rounded-2xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", boxShadow: "var(--shadow-lg)", maxHeight: "26rem", display: "flex", flexDirection: "column", overflowY: "hidden" }}
      >
        {body}
      </Popover>
    </div>
  );
}

function stampLabel(workout: WorkoutRecord, format: Intl.DateTimeFormat) {
  const stamp = workout.updated_at ?? workout.inserted_at;
  if (!stamp) return "";
  const date = new Date(stamp);
  return Number.isNaN(date.getTime()) ? "" : format.format(date);
}
