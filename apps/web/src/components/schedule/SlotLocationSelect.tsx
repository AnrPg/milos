"use client";

import { useEffect } from "react";

import type { FacilityLocation } from "@/api/facility";
import { useUiTranslations } from "@/i18n/ui";
import { Select } from "@/components/ui/Select";
import { membershipLocationScope } from "@/lib/location-scope";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Optional location of a class (ADR-097). Hidden for single-site gyms; an
 * archived location stays listed only while it is the current choice.
 * Branch-scoped staff (ADR-186) always pick one of their branches: the list
 * comes filtered from the API and "any location" is not offered.
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
  const { membership } = useSelectedMembershipRole();
  const scoped = membershipLocationScope(membership) !== "all";
  const options = locations.filter((location) => !location.archived_at || location.id === value);
  const firstActive = locations.find((location) => !location.archived_at)?.id;

  useEffect(() => {
    if (scoped && !value && firstActive) onChange(firstActive);
  }, [scoped, value, firstActive, onChange]);

  if (!firstActive) return null;

  return (
    <label className={className}>
      <span>{i18n("admSlotLocation")}</span>
      <Select
        className={selectClassName}
        onValueChange={(value) => onChange(value || null)}
        style={selectStyle}
        value={value ?? ""}
      >
        {scoped ? null : <option value="">{i18n("admSlotLocationAny")}</option>}
        {options.map((location) => (
          <option key={location.id} value={location.id}>{location.name}</option>
        ))}
      </Select>
    </label>
  );
}
