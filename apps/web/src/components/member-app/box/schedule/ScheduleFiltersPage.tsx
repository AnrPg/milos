"use client";

import { useTranslations } from "next-intl";

import {
  CLASS_AUDIENCES,
  CLASS_LEVELS,
  WORKOUT_FOCUSES,
  type ClassTypeRecord,
  type ScheduleCoach,
} from "@/api/schedule";
import { ChoiceChips, FilterPage, FilterSection, RangeSlider } from "@/components/filters/FilterPage";

import {
  DEFAULT_SCHEDULE_FILTERS,
  PACKAGE_ALL,
  FRIENDS_ALL,
  FRIENDS_ONLY,
  PACKAGE_ONLY,
  TIME_RANGE_BOUNDS,
  type BookedFilter,
  type DurationBand,
  type KindFilter,
  type FriendsChoice,
  type PackageChoice,
  type ScheduleFilters,
  type SpotsFilter,
} from "./schedule-filters";

function clock(minutes: number) {
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

/** Every Πρόγραμμα filter, in the order of the plan's catalog (§5a decision 2). */
export function ScheduleFiltersPage({
  filters,
  onChange,
  onClose,
  classTypes,
  coaches,
  resultCount,
}: {
  filters: ScheduleFilters;
  onChange: (filters: ScheduleFilters) => void;
  onClose: () => void;
  classTypes: ClassTypeRecord[];
  coaches: ScheduleCoach[];
  resultCount: number;
}) {
  const t = useTranslations("BoxSchedule");
  const update = (patch: Partial<ScheduleFilters>) => onChange({ ...filters, ...patch });
  const time = filters.time ?? TIME_RANGE_BOUNDS;

  return (
    <FilterPage
      title={t("filtersTitle")}
      resultCount={resultCount}
      onClose={onClose}
      onClear={() => onChange(DEFAULT_SCHEDULE_FILTERS)}
    >
      {classTypes.length > 0 ? (
        <FilterSection label={t("chipType")}>
          <ChoiceChips
            ariaLabel={t("chipType")}
            multiple
            options={classTypes.map((type) => ({ value: type.id, label: type.name }))}
            selected={filters.classTypeIds}
            onChange={(classTypeIds) => update({ classTypeIds })}
          />
        </FilterSection>
      ) : null}

      <FilterSection label={t("chipKind")}>
        <ChoiceChips<KindFilter>
          ariaLabel={t("chipKind")}
          multiple={false}
          options={[
            { value: "all", label: t("optionAll") },
            { value: "class", label: t("kindClass") },
            { value: "event", label: t("kindEvent") },
          ]}
          selected={[filters.kind]}
          onChange={([kind]) => update({ kind })}
        />
      </FilterSection>

      <FilterSection label={t("chipSpots")}>
        <ChoiceChips<SpotsFilter>
          ariaLabel={t("chipSpots")}
          multiple={false}
          options={[
            { value: "open", label: t("spots_open") },
            { value: "full_waitlist", label: t("spots_full_waitlist") },
            { value: "full", label: t("spots_full") },
            { value: "all", label: t("optionAll") },
          ]}
          selected={[filters.spots]}
          onChange={([spots]) => update({ spots })}
        />
      </FilterSection>

      <FilterSection label={t("package")}>
        <ChoiceChips<PackageChoice>
          ariaLabel={t("package")}
          multiple={false}
          options={[
            { value: PACKAGE_ONLY, label: t("chipPackage") },
            { value: PACKAGE_ALL, label: t("optionAll") },
          ]}
          selected={[filters.packageOnly ? PACKAGE_ONLY : PACKAGE_ALL]}
          onChange={([value]) => update({ packageOnly: value === PACKAGE_ONLY })}
        />
      </FilterSection>

      <FilterSection label={t("chipFriends")}>
        <ChoiceChips<FriendsChoice>
          ariaLabel={t("chipFriends")}
          multiple={false}
          options={[
            { value: FRIENDS_ONLY, label: t("friendsOnly") },
            { value: FRIENDS_ALL, label: t("optionAll") },
          ]}
          selected={[filters.friends ? FRIENDS_ONLY : FRIENDS_ALL]}
          onChange={([value]) => update({ friends: value === FRIENDS_ONLY })}
        />
      </FilterSection>

      <FilterSection label={t("chipLevel")}>
        <ChoiceChips
          ariaLabel={t("chipLevel")}
          multiple
          options={CLASS_LEVELS.map((value) => ({ value, label: t(`level_${value}`) }))}
          selected={filters.levels}
          onChange={(levels) => update({ levels })}
        />
      </FilterSection>

      {coaches.length > 0 ? (
        <FilterSection label={t("coach")}>
          <ChoiceChips
            ariaLabel={t("coach")}
            multiple
            options={coaches.map((coach) => ({ value: coach.id, label: coach.nickname }))}
            selected={filters.coachIds}
            onChange={(coachIds) => update({ coachIds })}
          />
        </FilterSection>
      ) : null}

      <FilterSection label={t("time")}>
        <RangeSlider
          min={TIME_RANGE_BOUNDS.from}
          max={TIME_RANGE_BOUNDS.to}
          step={30}
          value={time}
          format={clock}
          fromLabel={t("timeFrom")}
          toLabel={t("timeTo")}
          onChange={(next) =>
            update({
              time: next.from === TIME_RANGE_BOUNDS.from && next.to === TIME_RANGE_BOUNDS.to ? null : next,
            })
          }
        />
      </FilterSection>

      <FilterSection label={t("booked")}>
        <ChoiceChips<BookedFilter>
          ariaLabel={t("booked")}
          multiple={false}
          options={[
            { value: "all", label: t("optionAll") },
            { value: "mine", label: t("bookedMine") },
            { value: "mine_or_waitlist", label: t("bookedMineOrWaitlist") },
          ]}
          selected={[filters.booked]}
          onChange={([booked]) => update({ booked })}
        />
      </FilterSection>

      <FilterSection label={t("duration")}>
        <ChoiceChips<DurationBand>
          ariaLabel={t("duration")}
          multiple
          options={(["short", "medium", "long"] as const).map((value) => ({ value, label: t(`duration_${value}`) }))}
          selected={filters.durations}
          onChange={(durations) => update({ durations })}
        />
      </FilterSection>

      <FilterSection label={t("focus")} hint={t("focusHint")}>
        <ChoiceChips
          ariaLabel={t("focus")}
          multiple
          options={WORKOUT_FOCUSES.map((value) => ({ value, label: t(`focus_${value}`) }))}
          selected={filters.focus}
          onChange={(focus) => update({ focus })}
        />
      </FilterSection>

      <FilterSection label={t("audience")}>
        <ChoiceChips
          ariaLabel={t("audience")}
          multiple
          options={CLASS_AUDIENCES.map((value) => ({ value, label: t(`audience_${value}`) }))}
          selected={filters.audiences}
          onChange={(audiences) => update({ audiences })}
        />
      </FilterSection>
    </FilterPage>
  );
}
