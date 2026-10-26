"use client";

import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchSpaces } from "@/api/spaces";
import { useSession } from "@/components/session-provider";
import { spacesForBranches } from "@/components/spaces/floor-plan";
import { Select } from "@/components/ui/Select";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

/**
 * The space of a class (ADR-202), next to its branch. Only the spaces that
 * fit the branch are offered: the branch's own and the gym-wide ones (a class
 * created for several branches at once can only take a gym-wide space). A
 * space that no longer fits after the branch changes is cleared. Hidden when
 * the gym has no spaces or the viewer cannot see them.
 */
export function SlotSpaceSelect({
  locationIds,
  value,
  onChange,
  className,
  selectClassName,
  selectStyle,
}: {
  locationIds: (string | null | undefined)[];
  value: string | null | undefined;
  onChange: (value: string | null) => void;
  className?: string;
  selectClassName?: string;
  selectStyle?: React.CSSProperties;
}) {
  const t = useTranslations("Spaces");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const visible = ["view_spaces", "manage_spaces", "edit_space_details", "set_space_unavailable", "manage_schedule"].some((capability) => can(membership, capability));
  const spaces = useQuery({
    queryKey: ["staff", "spaces", { archived: false }],
    enabled: Boolean(token) && visible,
    queryFn: () => fetchSpaces(token, {}),
    staleTime: 60_000,
  });
  const options = spacesForBranches(spaces.data?.spaces ?? [], locationIds);
  const fits = !value || options.some((space) => space.id === value);
  const loaded = spaces.isSuccess;

  useEffect(() => {
    if (loaded && value && !fits) onChange(null);
  }, [loaded, value, fits, onChange]);

  if (!visible || options.length === 0) return null;

  return (
    <label className={className}>
      <span>{t("classSpace")}</span>
      <Select className={selectClassName} style={selectStyle} value={value ?? ""} data-testid="class-space-select" onValueChange={(next) => onChange(next || null)}>
        <option value="">{t("classSpaceNone")}</option>
        {options.map((space) => (
          <option key={space.id} value={space.id}>{space.name}</option>
        ))}
      </Select>
    </label>
  );
}
