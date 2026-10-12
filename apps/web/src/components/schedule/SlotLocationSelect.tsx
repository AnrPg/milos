"use client";

import type { FacilityLocation } from "@/api/facility";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Optional location of a class (ADR-097). Hidden for single-site gyms; an
 * archived location stays listed only while it is the current choice.
 */
export function SlotLocationSelect({
  locations,
  value,
  onChange,
  className,
  selectClassName,
  selectStyle,
}: {
  locations: FacilityLocation[];
  value: string | null | undefined;
  onChange: (value: string | null) => void;
  className?: string;
  selectClassName?: string;
  selectStyle?: React.CSSProperties;
}) {
  const i18n = useUiTranslations();
  const options = locations.filter((location) => !location.archived_at || location.id === value);
  if (!locations.some((location) => !location.archived_at)) return null;

  return (
    <label className={className}>
      <span>{i18n("admSlotLocation")}</span>
      <select
        className={selectClassName}
        onChange={(event) => onChange(event.target.value || null)}
        style={selectStyle}
        value={value ?? ""}
      >
        <option value="">{i18n("admSlotLocationAny")}</option>
        {options.map((location) => (
          <option key={location.id} value={location.id}>{location.name}</option>
        ))}
      </select>
    </label>
  );
}
