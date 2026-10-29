"use client";

import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { useInfiniteQuery, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  fetchSuggestedWorkoutChoices,
  searchWorkoutChoices,
  type WorkoutChoice,
} from "@/api/workout-choices";
import { fetchAdminWorkout, listWorkoutFolders } from "@/api/workouts";
import { CollapsibleFilterBar } from "@/components/filters/CollapsibleFilterBar";
import { resolveWorkoutIcon } from "@/components/workouts/library/library-folders";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { SPARK_CREATE_STYLE } from "@/lib/spark";

/**
 * The class form's WOD field (ADR-176: optional), built for libraries of
 * thousands. The form never loads the library:
 *
 * - Under an empty field, one tap takes the WOD the gym most likely wants:
 *   the one other classes already use that day, else one recently used for
 *   this class type.
 * - The picker opens on a short list of suggestions (that day, recent for the
 *   class type, newest). Anything else is found by searching title words, with
 *   type and folder filters behind the filter button, a page at a time on the
 *   server.
 * - "+ New WOD" sits on the field's label row (and on an empty search) to
 *   write one instead.
 *
 * A centred dialog on wider screens, a tall bottom sheet on phones.
 */

const WORKOUT_TYPES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery"] as const;
const SEARCH_DELAY_MS = 250;

export const workoutChoiceKey = (id: string) => ["workout-choice", id] as const;

function useDebounced<T>(value: T, delay: number) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

/** The suggestions a class gets, shared by the field's one-tap chips and the picker. */
function useSuggestions(token: string, date: string | null, classTypeId: string | null | undefined) {
  return useQuery({
    queryKey: ["workout-choices", "suggested", date, classTypeId ?? null],
    enabled: Boolean(token && date),
    queryFn: () => fetchSuggestedWorkoutChoices(token, { date: date!, classTypeId }),
    staleTime: 60_000,
  });
}

type Option = { key: string; choice: WorkoutChoice | null };

export function WodPicker({
  label,
  token,
  value,
  onChange,
  onCreateNew,
  date,
  classTypeId,
  classTypeName,
  noneHint,
  variant = "field",
}: {
  label: string;
  token: string;
  value: string | null;
  onChange: (workoutId: string | null) => void;
  /** Leaves the form for the WOD editor; the form comes back with the new WOD. */
  onCreateNew: () => void;
  /** The class's gym-local day (YYYY-MM-DD), for "that day" suggestions. */
  date: string | null;
  classTypeId?: string | null;
  classTypeName?: string | null;
  /** What "No WOD yet" means here (a class, or each class of a series). */
  noneHint?: string;
  /**
   * "field" is the form input. "actions" is for a class missing its WOD: two
   * plain calls to action («Choose a WOD», «+ New WOD») instead of a field.
   */
  variant?: "field" | "actions";
}) {
  const t = useTranslations("Schedule");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const id = useId();
  const labelId = `${id}-label`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);

  const suggestions = useSuggestions(token, date, classTypeId);
  // The chosen WOD's name: from the pick itself, else fetched once by id
  // (editing a class, or coming back from "+ New WOD").
  const chosen = useQuery({
    queryKey: workoutChoiceKey(value ?? ""),
    enabled: Boolean(token && value),
    queryFn: async (): Promise<WorkoutChoice> => {
      const workout = await fetchAdminWorkout(token, value!);
      return { id: workout.id, title: workout.title, type: workout.type, icon: workout.icon ?? null };
    },
    staleTime: Infinity,
  });
  const selected = value ? chosen.data ?? null : null;

  function choose(choice: WorkoutChoice | null) {
    if (choice) queryClient.setQueryData(workoutChoiceKey(choice.id), choice);
    onChange(choice?.id ?? null);
  }

  const sameDay = suggestions.data?.same_day ?? [];
  const quick = (sameDay.length ? sameDay : suggestions.data?.recent ?? []).slice(0, 2);

  const actions = variant === "actions";

  return (
    <div className="space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
      {actions ? (
        <div className="flex flex-wrap gap-2" role="group" aria-label={label}>
          <button
            ref={triggerRef}
            type="button"
            aria-haspopup="dialog"
            aria-expanded={open}
            className="grow whitespace-nowrap rounded-full px-4 py-2 text-sm font-semibold sm:grow-0"
            style={{ background: "var(--text)", color: "var(--bg)" }}
            onClick={() => setOpen(true)}
          >
            {t("wodPickerChoose")}
          </button>
          <button
            type="button"
            className="grow whitespace-nowrap rounded-full px-4 py-2 text-sm font-semibold sm:grow-0"
            style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border-strong)" }}
            onClick={onCreateNew}
          >
            + {t("wodPickerNew")}
          </button>
        </div>
      ) : (
        <>
          <div className="flex items-center justify-between gap-2">
            <span id={labelId}>{label}</span>
            <button type="button" className="rounded-full px-2.5 py-0.5 text-xs font-semibold" style={SPARK_CREATE_STYLE} onClick={onCreateNew}>
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
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)", paddingInlineEnd: value ? "3.25rem" : undefined }}
              onClick={() => setOpen(true)}
            >
              <span aria-hidden="true" className="w-6 shrink-0 text-center text-lg">
                {selected ? resolveWorkoutIcon(selected) : "○"}
              </span>
              <span id={`${id}-value`} className="min-w-0 flex-1">
                <span className="block truncate font-semibold" style={{ color: value ? "var(--text)" : "var(--muted)" }}>
                  {selected ? selected.title : value ? t("wodPickerChosen") : t("wodPickerNone")}
                </span>
                <span className="block truncate text-xs font-normal" style={{ color: "var(--muted)" }}>
                  {selected ? semanticLabel(selected.type, i18n) : value ? "" : t("wodPickerTapToChoose")}
                </span>
              </span>
              {value ? null : (
                <span aria-hidden="true" className="shrink-0" style={{ color: "var(--muted)" }}>
                  ⌕
                </span>
              )}
            </button>
            {value ? (
              <button
                type="button"
                aria-label={t("wodPickerClear")}
                className="absolute end-2 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-full text-base"
                style={{ color: "var(--muted)" }}
                onClick={() => choose(null)}
              >
                ×
              </button>
            ) : null}
          </div>
        </>
      )}

      {!value && quick.length ? (
        <div className="flex flex-wrap items-center gap-2 text-xs font-normal">
          <span>{sameDay.length ? t("wodPickerQuickSameDay") : t("wodPickerQuickRecent")}</span>
          {quick.map((choice) => (
            <button
              key={choice.id}
              type="button"
              aria-label={t("wodPickerUse", { title: choice.title })}
              className="inline-flex max-w-full items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold"
              style={{ background: "var(--panel)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
              onClick={() => choose(choice)}
            >
              <span aria-hidden="true">{resolveWorkoutIcon(choice)}</span>
              <span className="truncate">{choice.title}</span>
            </button>
          ))}
        </div>
      ) : null}

      {open ? (
        <WodPickerDialog
          label={label}
          token={token}
          value={value}
          date={date}
          classTypeName={classTypeName}
          suggestions={suggestions.data}
          suggestionsLoading={suggestions.isLoading}
          noneHint={noneHint}
          onChoose={(choice) => {
            choose(choice);
            setOpen(false);
          }}
          onCreateNew={onCreateNew}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </div>
  );
}

function WodPickerDialog({
  label,
  token,
  value,
  date,
  classTypeName,
  suggestions,
  suggestionsLoading,
  noneHint,
  onChoose,
  onCreateNew,
  onClose,
}: {
  label: string;
  token: string;
  value: string | null;
  date: string | null;
  classTypeName?: string | null;
  suggestions: ReturnType<typeof useSuggestions>["data"];
  suggestionsLoading: boolean;
  noneHint?: string;
  onChoose: (choice: WorkoutChoice | null) => void;
  onCreateNew: () => void;
  onClose: () => void;
}) {
  const t = useTranslations("Schedule");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const listId = useId();
  const [query, setQuery] = useState("");
  const [type, setType] = useState("");
  const [folderId, setFolderId] = useState("");
  const [active, setActive] = useState(0);
  // On a phone the list gets focus, not the search field, so the keyboard
  // doesn't cover the suggestions until the coach taps search.
  const [phone] = useState(() => typeof window.matchMedia === "function" && window.matchMedia("(max-width: 639px)").matches);
  const debouncedQuery = useDebounced(query.trim(), SEARCH_DELAY_MS);
  const searching = Boolean(debouncedQuery || type || folderId);

  const folders = useQuery({
    queryKey: ["workout-folders", "picker"],
    enabled: Boolean(token),
    queryFn: () => listWorkoutFolders(token),
    staleTime: 5 * 60_000,
  });

  const results = useInfiniteQuery({
    queryKey: ["workout-choices", "search", debouncedQuery, type, folderId],
    enabled: Boolean(token) && searching,
    initialPageParam: 0,
    queryFn: ({ pageParam }) => searchWorkoutChoices(token, { q: debouncedQuery, type, folderId, offset: pageParam }),
    getNextPageParam: (page) => page.next_offset ?? undefined,
    staleTime: 30_000,
  });

  const dayLabel = useMemo(() => {
    if (!date) return "";
    const [year, month, day] = date.split("-").map(Number);
    return new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(
      new Date(Date.UTC(year, month - 1, day)),
    );
  }, [date, locale]);

  const groups: Array<{ key: string; title: string | null; options: Option[] }> = searching
    ? [{ key: "results", title: null, options: (results.data?.pages ?? []).flatMap((page) => page.workouts).map((choice) => ({ key: choice.id, choice })) }]
    : [
        { key: "none", title: null, options: [{ key: "none", choice: null }] },
        { key: "same-day", title: t("wodPickerSameDay", { date: dayLabel }), options: toOptions(suggestions?.same_day) },
        {
          key: "recent",
          title: classTypeName ? t("wodPickerRecent", { classType: classTypeName }) : t("wodPickerRecentAny"),
          options: toOptions(suggestions?.recent),
        },
        { key: "newest", title: t("wodPickerNewest"), options: toOptions(suggestions?.newest) },
      ].filter((group) => group.options.length > 0);
  const options = groups.flatMap((group) => group.options);
  const activeIndex = Math.min(active, Math.max(0, options.length - 1));
  const optionId = (index: number) => `${listId}-option-${index}`;
  const filterCount = (type ? 1 : 0) + (folderId ? 1 : 0);
  const noResults = searching && !results.isLoading && options.length === 0;

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (!(event.target instanceof HTMLInputElement) || event.target.type !== "search") return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      setActive(Math.min(options.length - 1, Math.max(0, activeIndex + step)));
    } else if (event.key === "Enter" && options[activeIndex]) {
      event.preventDefault();
      onChoose(options[activeIndex].choice);
    }
  }

  let index = -1;

  return (
    <Dialog
      onClose={onClose}
      title={label}
      size="lg"
      variant="sheet"
      plainBody
      panelClassName="h-[92dvh] sm:h-[min(44rem,88dvh)]"
    >
      <div className="flex min-h-0 flex-1 flex-col" onKeyDown={onKeyDown}>
        <div className="shrink-0 px-4 pb-3 sm:px-6">
          <CollapsibleFilterBar
            ariaLabel={t("wodPickerFilters")}
            search={{
              value: query,
              onChange: (next) => {
                setQuery(next);
                setActive(0);
              },
              placeholder: t("wodPickerSearch"),
              ariaLabel: t("wodPickerSearch"),
              maxLength: 200,
            }}
            activeCount={filterCount}
            onClear={() => {
              setType("");
              setFolderId("");
            }}
          >
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="space-y-1 text-xs font-semibold" style={{ color: "var(--muted)" }}>
                <span>{t("wodPickerType")}</span>
                <Select className="w-full rounded-xl px-3 py-2 text-sm" value={type} onValueChange={(next) => { setType(next); setActive(0); }}>
                  <option value="">{t("wodPickerAny")}</option>
                  {WORKOUT_TYPES.map((item) => (
                    <option key={item} value={item}>{semanticLabel(item, i18n)}</option>
                  ))}
                </Select>
              </label>
              <label className="space-y-1 text-xs font-semibold" style={{ color: "var(--muted)" }}>
                <span>{t("wodPickerFolder")}</span>
                <Select className="w-full rounded-xl px-3 py-2 text-sm" value={folderId} onValueChange={(next) => { setFolderId(next); setActive(0); }}>
                  <option value="">{t("wodPickerAny")}</option>
                  {(folders.data ?? []).map((folder) => (
                    <option key={folder.id} value={folder.id}>{folder.name}</option>
                  ))}
                </Select>
              </label>
            </div>
          </CollapsibleFilterBar>
        </div>

        <div
          id={listId}
          role="listbox"
          aria-label={label}
          tabIndex={-1}
          data-autofocus={phone ? "" : undefined}
          aria-activedescendant={options[activeIndex] ? optionId(activeIndex) : undefined}
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-2 outline-none pb-[max(1rem,env(safe-area-inset-bottom))] sm:px-4"
        >
          {groups.map((group) => (
            <div key={group.key} role="group" aria-label={group.title ?? undefined} className="pb-2">
              {group.title ? (
                <p className="px-3 pb-1 pt-3 text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
                  {group.title}
                </p>
              ) : null}
              {group.options.map((option) => {
                index += 1;
                const position = index;
                return (
                  <ChoiceRow
                    key={`${group.key}-${option.key}`}
                    id={optionId(position)}
                    active={position === activeIndex}
                    selected={(option.choice?.id ?? null) === value}
                    icon={option.choice ? resolveWorkoutIcon(option.choice) : "○"}
                    title={option.choice ? option.choice.title : t("wodPickerNone")}
                    detail={option.choice ? semanticLabel(option.choice.type, i18n) : noneHint ?? t("wodPickerNoneHint")}
                    onHover={() => setActive(position)}
                    onChoose={() => onChoose(option.choice)}
                  />
                );
              })}
            </div>
          ))}

          {(searching ? results.isLoading : suggestionsLoading) ? (
            <p className="px-3 py-4 text-sm" role="status" style={{ color: "var(--muted)" }}>
              {t("wodPickerLoading")}
            </p>
          ) : null}

          {searching && results.hasNextPage ? (
            <div className="flex justify-center py-3">
              <button
                type="button"
                disabled={results.isFetchingNextPage}
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                onClick={() => void results.fetchNextPage()}
              >
                {results.isFetchingNextPage ? t("wodPickerLoading") : t("wodPickerShowMore")}
              </button>
            </div>
          ) : null}

          {noResults ? (
            <EmptyState>
              <p>{debouncedQuery ? t("wodPickerNoMatch", { query: debouncedQuery }) : t("wodPickerNoFilterMatch")}</p>
              <button type="button" className="rounded-full px-3 py-1.5 text-xs font-semibold" style={SPARK_CREATE_STYLE} onClick={onCreateNew}>
                + {t("wodPickerNew")}
              </button>
            </EmptyState>
          ) : null}

          {!searching && !suggestionsLoading ? (
            <p className="px-3 pb-2 pt-3 text-xs" style={{ color: "var(--dim)" }}>
              {t("wodPickerSearchHint")}
            </p>
          ) : null}
        </div>
      </div>
    </Dialog>
  );
}

function toOptions(choices: WorkoutChoice[] | undefined): Option[] {
  return (choices ?? []).map((choice) => ({ key: choice.id, choice }));
}

function ChoiceRow({
  id,
  active,
  selected,
  icon,
  title,
  detail,
  onHover,
  onChoose,
}: {
  id: string;
  active: boolean;
  selected: boolean;
  icon: string;
  title: string;
  detail: string;
  onHover: () => void;
  onChoose: () => void;
}) {
  return (
    <div
      id={id}
      role="option"
      aria-selected={selected}
      className="flex min-h-12 cursor-pointer items-center gap-3 rounded-xl px-3 py-2.5"
      style={{ background: active ? "var(--panel-muted)" : "transparent" }}
      onMouseEnter={onHover}
      onClick={onChoose}
    >
      <span aria-hidden="true" className="w-6 shrink-0 text-center text-lg">
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
          {title}
        </span>
        {detail ? (
          <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>
            {detail}
          </span>
        ) : null}
      </span>
      {selected ? (
        <span aria-hidden="true" className="shrink-0 text-sm font-bold" style={{ color: "var(--primary)" }}>
          ✓
        </span>
      ) : null}
    </div>
  );
}

function EmptyState({ children }: { children: ReactNode }) {
  return (
    <div className="space-y-3 px-3 py-4 text-sm" style={{ color: "var(--muted)" }}>
      {children}
    </div>
  );
}
