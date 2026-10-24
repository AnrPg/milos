"use client";

import { useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import type { Neighbourhood } from "@/api/around";
import { getBoxVocabulary } from "@/api/public-profile";
import type { SavedFilter } from "@/api/saved-filters";
import { COMMON_LANGUAGES, languageNames } from "@/components/admin/public-page/languages";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { FilterChipRow, FilterMenuChip, type FilterChip } from "@/components/filters/FilterChipRow";
import { ChoiceChips, FilterPage, FilterSection, RangeSlider } from "@/components/filters/FilterPage";
import { DateInput } from "@/components/ui/DateInput";
import { isoDay, todayYmd } from "@/lib/calendar-grid";
import { useDebounced } from "@/hooks/useDebounced";

import {
  ACCESSIBLE_AMENITY,
  CHIP_DISCIPLINES,
  DAY_TIMES,
  DEFAULT_FILTER,
  DEFAULT_RADIUS_KM,
  KIND_ORDER,
  LEVELS,
  MAX_NEIGHBOURHOODS,
  PRICE_CAP_CENTS,
  PRICE_SLIDER,
  RADIUS_STEPS,
  WHENS,
  activeFilterCount,
  applyChip,
  chipModel,
  isMine,
  isPriceCap,
  lastRangeDay,
  priceSliderValue,
  radiusChip,
  sameFilter,
  toggleKind,
  toggleFree,
  toggleMine,
  togglePriceCap,
  toggleValue,
  withDates,
  withPriceRange,
  withWhen,
  parseFilter,
  type AroundFilter,
  type DayTime,
  type When,
} from "./around";
import { useMyInterests } from "@/components/interests/InterestsEditor";

import { PlaceOption, PlacesAttribution, useAroundError, useNeighbourhoodName } from "./AreaPicker";
import { useAround, useAroundArea, useNeighbourhoodSearch, useResolvePlace, useSavedFilterActions } from "./use-around";

/** «2,5 km» in the reader's numbers. */
export function useKm() {
  const locale = useLocale();
  const t = useTranslations("Around");
  return (km: number) => t("km", { km: new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(km) });
}

/**
 * The Γύρω μου chip row (vision §7.2, mockup `near`): «Φίλτρα (n)», «Τα
 * αθλήματά μου», «Πότε» and «Δωρεάν», and nothing else, so it fits a 320 px
 * phone in every language without scrolling sideways (two balanced lines when
 * one is too narrow). Everything else, saved combinations included, is in the
 * sheet «Φίλτρα (n)» opens, and counts in its (n).
 */
export function AroundChipRow({ resultCount, onShowMap }: { resultCount: number; onShowMap?: () => void }) {
  const t = useTranslations("Around");
  const { filter, setFilter, saved } = useAround();
  const [sheet, setSheet] = useState(false);
  const [saving, setSaving] = useState(false);
  const [managing, setManaging] = useState<SavedFilter | null>(null);
  const count = activeFilterCount(filter);
  // ADR-183: what the person does is one tap away, never applied on its own.
  const mine = useMyInterests().data?.disciplines ?? [];

  const modelChips: FilterChip[] = chipModel(filter).map((chip) =>
    chip.kind === "toggle"
      ? {
          key: chip.key,
          kind: "toggle",
          label: t("costFree"),
          active: chip.active,
          onToggle: () => setFilter(applyChip(filter, chip.key)),
        }
      : {
          key: chip.key,
          kind: "menu",
          label: t("chipWhen"),
          options: chip.options.map((value) => ({ value, label: t(["when", value].join("_")) })),
          selected: chip.selected,
          multiple: chip.multiple,
          onChange: (values: string[]) => setFilter(applyChip(filter, chip.key, values)),
        },
  );
  const chips: FilterChip[] =
    mine.length > 0
      ? [
          {
            key: "mine",
            kind: "toggle",
            label: t("myDisciplines"),
            active: isMine(filter, mine),
            onToggle: () => setFilter(toggleMine(filter, mine)),
          },
          ...modelChips,
        ]
      : modelChips;

  return (
    <>
      <FilterChipRow
        fit
        ariaLabel={t("filtersLabel")}
        activeCount={count}
        onOpenFilters={() => setSheet(true)}
        onClear={() => setFilter(DEFAULT_FILTER)}
        chips={chips}
      />
      {sheet
        ? createPortal(
            <AroundFilterSheet
              resultCount={resultCount}
              mine={mine}
              saved={saved.map((entry) => (
                <SavedChip
                  key={entry.id}
                  entry={entry}
                  active={sameFilter(parseFilter(entry.params), filter)}
                  onApply={() => setFilter(parseFilter(entry.params))}
                  onManage={() => setManaging(entry)}
                />
              ))}
              onClose={() => setSheet(false)}
              onSave={() => setSaving(true)}
              onShowMap={
                onShowMap
                  ? () => {
                      setSheet(false);
                      onShowMap();
                    }
                  : undefined
              }
            />,
            document.body,
          )
        : null}
      {saving ? <SaveFilterSheet filter={filter} onClose={() => setSaving(false)} /> : null}
      {managing ? (
        <ManageFilterSheet
          entry={saved.find((entry) => entry.id === managing.id) ?? managing}
          onClose={() => setManaging(null)}
        />
      ) : null}
    </>
  );
}

/** «≤ 3 km ▾», on the line of «Αλλαγή περιοχής» (and «Δες όλα»'s back link); also in the sheet as the slider. */
export function RadiusChip() {
  const t = useTranslations("Around");
  const km = useKm();
  const { filter, setFilter } = useAround();
  const chip = radiusChip(filter);
  return (
    <FilterMenuChip
      // The radius always has a value: it reads as a filter in use only when it is not the default.
      active={filter.radius_km !== DEFAULT_RADIUS_KM}
      chip={{
        key: chip.key,
        kind: "menu",
        label: t("chipRadius"),
        options: chip.options.map((value) => ({ value, label: t("radiusChip", { distance: km(Number(value)) }) })),
        selected: chip.selected,
        multiple: false,
        onChange: (values) => setFilter(applyChip(filter, "radius", values)),
      }}
    />
  );
}

const chipClass = "flex h-9 items-center gap-1.5 whitespace-nowrap px-3 text-sm font-semibold";

/** A saved combination: tap applies it; ⋯ (or a long press) opens rename, alert and delete. */
function SavedChip({ entry, active, onApply, onManage }: { entry: SavedFilter; active: boolean; onApply: () => void; onManage: () => void }) {
  const t = useTranslations("Around");
  const timer = useRef<number | null>(null);
  const longPressed = useRef(false);
  const border = `1px solid ${active ? "var(--primary)" : "var(--border)"}`;
  const background = active ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)";
  const cancel = () => {
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = null;
  };

  return (
    <span className="flex min-w-0 max-w-full">
      <button
        type="button"
        aria-pressed={active}
        onPointerDown={() => {
          longPressed.current = false;
          timer.current = window.setTimeout(() => {
            longPressed.current = true;
            onManage();
          }, 550);
        }}
        onPointerUp={cancel}
        onPointerLeave={cancel}
        onContextMenu={(event) => {
          event.preventDefault();
          cancel();
          longPressed.current = true;
          onManage();
        }}
        onClick={() => {
          if (longPressed.current) return;
          onApply();
        }}
        className={`${chipClass} min-w-0 rounded-l-full pl-3.5`}
        style={{ background, border, borderRight: "none", color: active ? "var(--text)" : "var(--text-soft)" }}
      >
        {entry.alert ? <span aria-hidden="true">🔔</span> : null}
        <span className="truncate">{entry.name}</span>
        {entry.alert ? <span className="sr-only">{t("alertOnShort")}</span> : null}
      </button>
      <button
        type="button"
        onClick={onManage}
        aria-label={t("savedOptions", { name: entry.name })}
        aria-haspopup="dialog"
        className={`${chipClass} shrink-0 rounded-r-full pl-1.5 pr-2.5`}
        style={{ background, border, borderLeft: "none", color: "var(--dim)" }}
      >
        <span aria-hidden="true">⋯</span>
      </button>
    </span>
  );
}

/** «Αποθήκευση ως…»: a name for the current combination («ΣΚ κοντά»). */
function SaveFilterSheet({ filter, onClose }: { filter: AroundFilter; onClose: () => void }) {
  const t = useTranslations("Around");
  const aroundError = useAroundError();
  const { save } = useSavedFilterActions();
  const [name, setName] = useState("");
  const inputId = useId();
  const formId = useId();
  const trimmed = name.trim();

  return (
    <Sheet
      labelId="around-save-filter"
      title={t("saveAsTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary type="submit" form={formId} disabled={!trimmed || save.isPending}>
            {t("save")}
          </SheetButton>
        </>
      }
    >
      <form
        id={formId}
        className="flex flex-col gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (trimmed) save.mutate({ name: trimmed, filter }, { onSuccess: onClose });
        }}
      >
        <label htmlFor={inputId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("saveAsName")}
        </label>
        <input
          id={inputId}
          value={name}
          maxLength={40}
          onChange={(event) => setName(event.target.value)}
          placeholder={t("saveAsPlaceholder")}
          className="min-h-11 rounded-2xl px-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("saveAsHint")}</p>
        <ErrorLine message={aroundError(save.error)} />
      </form>
    </Sheet>
  );
}

/** A saved filter's options: «Ειδοποίησέ με», rename and delete. */
function ManageFilterSheet({ entry, onClose }: { entry: SavedFilter; onClose: () => void }) {
  const t = useTranslations("Around");
  const aroundError = useAroundError();
  const { alert, rename, remove } = useSavedFilterActions();
  const [name, setName] = useState(entry.name);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const inputId = useId();
  const alertId = useId();
  const trimmed = name.trim();
  const error = alert.error ?? rename.error ?? remove.error;

  return (
    <Sheet labelId="around-manage-filter" eyebrow={t("savedFilter")} title={entry.name} onClose={onClose}>
      <div className="flex flex-col gap-5">
        <div className="flex items-center justify-between gap-4">
          <span className="min-w-0">
            <span id={alertId} className="block text-sm font-bold" style={{ color: "var(--text)" }}>{t("alertToggle")}</span>
            <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("alertHint")}</span>
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={entry.alert}
            aria-labelledby={alertId}
            disabled={alert.isPending}
            onClick={() => alert.mutate({ id: entry.id, enabled: !entry.alert })}
            className="relative h-8 w-14 shrink-0 rounded-full transition-colors disabled:opacity-60"
            style={{ background: entry.alert ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
          >
            <span
              aria-hidden="true"
              className="absolute top-1 h-5 w-5 rounded-full transition-all"
              style={{ left: entry.alert ? "1.9rem" : "0.25rem", background: entry.alert ? "var(--bg)" : "var(--text)" }}
            />
          </button>
        </div>

        <form
          className="flex flex-col gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            if (trimmed && trimmed !== entry.name) rename.mutate({ entry, name: trimmed }, { onSuccess: onClose });
          }}
        >
          <label htmlFor={inputId} className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("rename")}</label>
          <div className="flex gap-2">
            <input
              id={inputId}
              value={name}
              maxLength={40}
              onChange={(event) => setName(event.target.value)}
              className="min-h-11 min-w-0 flex-1 rounded-2xl px-3 text-sm"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
            <button
              type="submit"
              disabled={!trimmed || trimmed === entry.name || rename.isPending}
              className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
              style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            >
              {t("save")}
            </button>
          </div>
        </form>

        {confirmDelete ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm" style={{ color: "var(--text)" }}>{t("deleteConfirm", { name: entry.name })}</p>
            <div className="flex gap-2">
              <SheetButton onClick={() => setConfirmDelete(false)}>{t("cancel")}</SheetButton>
              <SheetButton primary disabled={remove.isPending} onClick={() => remove.mutate(entry.id, { onSuccess: onClose })}>
                {t("delete")}
              </SheetButton>
            </div>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setConfirmDelete(true)}
            className="min-h-11 rounded-2xl text-sm font-bold"
            style={{ color: "var(--danger)", border: "1px solid var(--border)" }}
          >
            {t("delete")}
          </button>
        )}
        <ErrorLine message={aroundError(error)} />
      </div>
    </Sheet>
  );
}

/** Every Γύρω μου filter (mockup `filters`), applied as you tap; «Δείξε N» closes. */
function AroundFilterSheet({
  resultCount,
  mine,
  saved,
  onClose,
  onSave,
  onShowMap,
}: {
  resultCount: number;
  /** The person's disciplines (ADR-183): offered first. */
  mine: string[];
  /** The saved combinations («ΣΚ κοντά»), tap to apply. */
  saved: React.ReactNode[];
  onClose: () => void;
  onSave: () => void;
  onShowMap?: () => void;
}) {
  const t = useTranslations("Around");
  const tags = useTranslations("BoxTags");
  const levels = useTranslations("BoxSchedule");
  const locale = useLocale();
  const km = useKm();
  const placeName = useNeighbourhoodName();
  const { filter, setFilter } = useAround();
  const area = useAroundArea();
  const vocabulary = useQuery({ queryKey: ["box-vocabulary"], queryFn: getBoxVocabulary, staleTime: Infinity });
  const languages = useMemo(() => languageNames(locale), [locale]);
  const [allDisciplines, setAllDisciplines] = useState(false);
  const [placeQuery, setPlaceQuery] = useState("");
  const placeSearch = useNeighbourhoodSearch(useDebounced(placeQuery, 250));
  const resolvePlace = useResolvePlace();
  const aroundError = useAroundError();
  const [known, setKnown] = useState<Record<string, Neighbourhood>>({});
  const update = (patch: Partial<AroundFilter>) => setFilter({ ...filter, ...patch });

  const places = useMemo(() => {
    const byId = new Map<string, Neighbourhood>();
    for (const place of [...(area.data ?? []), ...Object.values(known)]) byId.set(place.id, place);
    return byId;
  }, [area.data, known]);
  const placeChips = Array.from(new Set([...(area.data ?? []).map((place) => place.id), ...filter.neighbourhood_ids]));
  const stepIndex = RADIUS_STEPS.reduce(
    (best, step, index) => (Math.abs(step - filter.radius_km) < Math.abs(RADIUS_STEPS[best] - filter.radius_km) ? index : best),
    0,
  );
  const disciplineKeys = allDisciplines
    ? (vocabulary.data?.discipline_groups ?? []).flatMap((group) => group.items)
    : Array.from(new Set([...mine, ...CHIP_DISCIPLINES, ...filter.disciplines]));
  const accessible = filter.amenities.includes(ACCESSIBLE_AMENITY);
  const euros = (cents: number) =>
    new Intl.NumberFormat(locale, { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(cents / 100);
  const dateFrom = filter.when === "range" ? filter.date_from : null;
  const dateTo = filter.when === "range" ? filter.date_to : null;
  const today = isoDay(todayYmd());

  return (
    <FilterPage title={t("filtersTitle")} resultCount={resultCount} onClose={onClose} onClear={() => setFilter(DEFAULT_FILTER)}>
      {saved.length > 0 ? (
        <FilterSection label={t("sectionSaved")}>
          <div role="group" aria-label={t("sectionSaved")} className="flex flex-wrap gap-2">
            {saved}
          </div>
        </FilterSection>
      ) : null}

      <FilterSection label={t("sectionWhere")} hint={filter.neighbourhood_ids.length > 0 ? t("whereFromPlaces") : km(filter.radius_km)}>
        <label className="flex flex-col gap-2">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("radius")}</span>
          <input
            type="range"
            min={0}
            max={RADIUS_STEPS.length - 1}
            step={1}
            value={stepIndex}
            aria-valuetext={km(RADIUS_STEPS[stepIndex])}
            onChange={(event) => update({ radius_km: RADIUS_STEPS[Number(event.target.value)] })}
            className="w-full accent-[var(--primary)]"
          />
        </label>
        {placeChips.length > 0 ? (
          <div role="group" aria-label={t("neighbourhoods")} className="flex flex-wrap gap-2">
            {placeChips.map((id) => {
              const on = filter.neighbourhood_ids.includes(id);
              const place = places.get(id);
              return (
                <button
                  key={id}
                  type="button"
                  aria-pressed={on}
                  disabled={!on && filter.neighbourhood_ids.length >= MAX_NEIGHBOURHOODS}
                  onClick={() => update({ neighbourhood_ids: toggleValue(filter.neighbourhood_ids, id) })}
                  className="min-h-10 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
                  style={{
                    background: on ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
                    border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
                    color: on ? "var(--text)" : "var(--text-soft)",
                  }}
                >
                  {place ? placeName(place) : t("placeUnknown")}
                </button>
              );
            })}
            {onShowMap ? (
              <button
                type="button"
                onClick={onShowMap}
                className="min-h-10 rounded-full px-4 text-sm font-semibold"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                <span aria-hidden="true">📍 </span>
                {t("mapChip")}
              </button>
            ) : null}
          </div>
        ) : null}
        <label className="sr-only" htmlFor="around-filter-place">{t("addNeighbourhood")}</label>
        <input
          id="around-filter-place"
          type="search"
          value={placeQuery}
          onChange={(event) => setPlaceQuery(event.target.value)}
          placeholder={t("addNeighbourhood")}
          autoComplete="off"
          className="min-h-11 w-full rounded-2xl px-3 text-sm"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        {placeQuery.trim().length >= 2 && (placeSearch.data?.places ?? []).length > 0 ? (
          <ul aria-live="polite" className="flex flex-col">
            {(placeSearch.data?.places ?? [])
              .filter((place) => !filter.neighbourhood_ids.includes(place.id))
              .slice(0, 6)
              .map((place) => (
                <li key={place.id}>
                  <button
                    type="button"
                    disabled={filter.neighbourhood_ids.length >= MAX_NEIGHBOURHOODS || resolvePlace.isPending}
                    aria-busy={resolvePlace.isPending && resolvePlace.variables?.id === place.id}
                    onClick={() =>
                      resolvePlace.mutate(place, {
                        onSuccess: (stored) => {
                          setKnown((current) => ({ ...current, [stored.id]: stored }));
                          if (!filter.neighbourhood_ids.includes(stored.id))
                            update({ neighbourhood_ids: [...filter.neighbourhood_ids, stored.id] });
                          setPlaceQuery("");
                        },
                      })
                    }
                    className="flex min-h-11 w-full items-center justify-between gap-3 rounded-xl px-2 py-1 text-left text-sm disabled:opacity-50"
                    style={{ color: "var(--text)" }}
                  >
                    <PlaceOption place={place} busy={resolvePlace.isPending && resolvePlace.variables?.id === place.id} />
                  </button>
                </li>
              ))}
          </ul>
        ) : null}
        <ErrorLine message={aroundError(resolvePlace.error)} />
        {placeQuery.trim().length >= 2 ? <PlacesAttribution /> : null}
      </FilterSection>

      <FilterSection label={t("sectionWhat")}>
        <div role="group" aria-label={t("sectionWhat")} className="flex flex-wrap gap-2">
          {KIND_ORDER.map((kind) => (
            <ToggleChip key={kind} on={filter.kinds.includes(kind)} onClick={() => setFilter(toggleKind(filter, kind))}>
              {t(["kind", kind].join("_"))}
            </ToggleChip>
          ))}
        </div>
        {!filter.kinds.includes("posts") ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("postsOffHint")}</p> : null}
      </FilterSection>

      <FilterSection label={t("sectionDiscipline")}>
        <ChoiceChips
          ariaLabel={t("sectionDiscipline")}
          multiple
          options={disciplineKeys.map((key) => ({ value: key, label: tags(["discipline", key].join(".")) }))}
          selected={filter.disciplines}
          onChange={(disciplines) => update({ disciplines })}
        />
        {vocabulary.data ? (
          <button
            type="button"
            aria-expanded={allDisciplines}
            onClick={() => setAllDisciplines((value) => !value)}
            className="self-start text-sm font-semibold underline"
            style={{ color: "var(--text)" }}
          >
            {allDisciplines ? t("fewerDisciplines") : t("allDisciplines")}
          </button>
        ) : null}
      </FilterSection>

      <FilterSection label={t("sectionWhen")} hint={t("whenHint")}>
        <div role="group" aria-label={t("dates")} className="grid grid-cols-2 gap-2">
          <DateInput
            aria-label={t("dateFrom")}
            placeholder={t("dateFrom")}
            value={dateFrom ?? ""}
            min={today}
            onValueChange={(value) => setFilter(withDates(filter, value || null, value ? dateTo : null))}
            className="min-h-11 w-full rounded-2xl px-3 text-sm"
          />
          <DateInput
            aria-label={t("dateTo")}
            placeholder={t("dateTo")}
            value={dateTo && dateTo !== dateFrom ? dateTo : ""}
            min={dateFrom ?? today}
            max={dateFrom ? lastRangeDay(dateFrom) : undefined}
            onValueChange={(value) => setFilter(withDates(filter, dateFrom, value || dateFrom))}
            className="min-h-11 w-full rounded-2xl px-3 text-sm"
          />
        </div>
        <ChoiceChips<When>
          ariaLabel={t("sectionWhen")}
          multiple
          options={WHENS.map((when) => ({ value: when, label: t(["when", when].join("_")) }))}
          selected={filter.when && filter.when !== "range" ? [filter.when] : []}
          onChange={(values) => setFilter(withWhen(filter, values.find((value) => value !== filter.when) ?? null))}
        />
        <ChoiceChips<DayTime>
          ariaLabel={t("dayTimes")}
          multiple
          options={DAY_TIMES.map((time) => ({ value: time, label: t(["time", time].join("_")) }))}
          selected={filter.times}
          onChange={(times) => update({ times })}
        />
      </FilterSection>

      <FilterSection label={t("sectionCost")}>
        <RangeSlider
          min={PRICE_SLIDER.min}
          max={PRICE_SLIDER.max}
          step={PRICE_SLIDER.step}
          value={priceSliderValue(filter)}
          format={(cents) => (cents >= PRICE_SLIDER.max ? t("priceOpenEnd", { price: euros(cents) }) : euros(cents))}
          fromLabel={t("priceFrom")}
          toLabel={t("priceTo")}
          onChange={(range) => setFilter(withPriceRange(filter, range))}
        />
        <div role="group" aria-label={t("sectionCost")} className="flex flex-wrap gap-2">
          <ToggleChip on={filter.cost.includes("free")} onClick={() => setFilter(toggleFree(filter))}>
            {t("costFree")}
          </ToggleChip>
          <ToggleChip on={isPriceCap(filter)} onClick={() => setFilter(togglePriceCap(filter))}>
            {t("priceCap", { price: euros(PRICE_CAP_CENTS) })}
          </ToggleChip>
          <ToggleChip on={filter.cost.includes("trial")} onClick={() => update({ cost: toggleValue(filter.cost, "trial") })}>
            {t("costTrial")}
          </ToggleChip>
        </div>
      </FilterSection>

      <FilterSection label={t("sectionAudience")}>
        <ChoiceChips
          ariaLabel={t("sectionAudience")}
          multiple
          options={(vocabulary.data?.audiences ?? ["beginners", "women_only", "over_40"]).map((key) => ({
            value: key,
            label: tags(["audience", key].join(".")),
          }))}
          selected={filter.audiences}
          onChange={(audiences) => update({ audiences })}
        />
      </FilterSection>

      <FilterSection label={t("sectionLevel")} hint={t("levelHint")}>
        <ChoiceChips
          ariaLabel={t("sectionLevel")}
          multiple
          options={LEVELS.map((level) => ({ value: level, label: levels(`level_${level}`) }))}
          selected={filter.levels}
          onChange={(values) => update({ levels: values as typeof filter.levels })}
        />
      </FilterSection>

      <FilterSection label={t("sectionLanguage")}>
        <ChoiceChips
          ariaLabel={t("sectionLanguage")}
          multiple
          options={Array.from(new Set([...COMMON_LANGUAGES.slice(0, 6), ...filter.languages])).map((code) => ({
            value: code,
            label: languages(code).own,
          }))}
          selected={filter.languages}
          onChange={(values) => update({ languages: values })}
        />
      </FilterSection>

      <FilterSection label={t("sectionAccessible")}>
        <ToggleChip
          on={accessible}
          onClick={() => update({ amenities: toggleValue(filter.amenities, ACCESSIBLE_AMENITY) })}
        >
          {t("accessible")}
        </ToggleChip>
      </FilterSection>

      <button
        type="button"
        onClick={onSave}
        className="min-h-12 rounded-2xl text-sm font-bold"
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
      >
        {t("saveAs")}
      </button>
    </FilterPage>
  );
}

function ToggleChip({ on, onClick, children }: { on: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={onClick}
      className="min-h-10 self-start rounded-full px-4 text-sm font-semibold"
      style={{
        background: on ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
        border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
        color: on ? "var(--text)" : "var(--text-soft)",
      }}
    >
      {children}
    </button>
  );
}
