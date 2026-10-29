"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useCallback, type CSSProperties } from "react";

import { fetchWorkoutAuthoringSettings, WOD_ASSISTANT_AVAILABILITY_KEY } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { Select } from "@/components/ui/Select";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { isWorkoutType, offeredWorkoutTypeGroups, workoutTypeFamily, type WorkoutType } from "@/lib/workout-types";

/** The translated name of a workout kind or family (ADR-275); unknown values read as words, never raw keys. */
export function useWorkoutTypeLabels() {
  const t = useTranslations("WorkoutTypes");
  const i18n = useUiTranslations();
  const type = useCallback((value: string | null | undefined) => semanticLabel(value, i18n), [i18n]);
  const family = useCallback(
    (value: string | null | undefined) => {
      const known = workoutTypeFamily(value) ?? value;
      return known ? t(`family.${known}`) : "";
    },
    [t],
  );
  return { type, family };
}

type Props = {
  value: WorkoutType | "";
  onChange: (value: WorkoutType) => void;
  /** Shown while nothing is chosen. */
  placeholder: string;
  invalid?: boolean;
  className?: string;
  style?: CSSProperties;
};

/**
 * The «Τύπος προπόνησης» picker (ADR-275): the gym's kinds from its
 * settings, grouped by family. A workout's own kind stays listed even when
 * the gym hides it, so opening an old workout never blanks its kind.
 */
export function WorkoutTypeSelect({ value, onChange, placeholder, invalid = false, className, style }: Props) {
  const labels = useWorkoutTypeLabels();
  const { tokens } = useSession();
  const settings = useQuery({
    queryKey: WOD_ASSISTANT_AVAILABILITY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutAuthoringSettings(tokens!.access_token),
    staleTime: 60_000,
  });
  const groups = offeredWorkoutTypeGroups(settings.data?.workout_types, value || null);

  return (
    <Select
      className={className}
      style={style}
      value={value}
      onValueChange={(next) => {
        if (isWorkoutType(next)) onChange(next);
      }}
      aria-invalid={invalid}
      data-testid="workout-type-select"
    >
      <option value="" disabled>
        {placeholder}
      </option>
      {workoutTypeOptionGroups(groups, labels)}
    </Select>
  );
}

/** `<optgroup>`s of workout kinds by family, for any `Select` (filters included). */
export function workoutTypeOptionGroups(
  groups: ReturnType<typeof offeredWorkoutTypeGroups>,
  labels: ReturnType<typeof useWorkoutTypeLabels>,
) {
  return groups.map((group) => (
    <optgroup key={group.family} label={labels.family(group.family)}>
      {group.types.map((type) => (
        <option key={type} value={type}>
          {labels.type(type)}
        </option>
      ))}
    </optgroup>
  ));
}
