"use client";

import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-115: assignment pickers list members next to athletes; members are
 * labelled so staff know the assignment depends on the member's package.
 */
export function AssigneeRoleBadge({ role }: { role?: string | null }) {
  const i18n = useUiTranslations();
  if (role !== "member") return null;

  return (
    <span
      className="ms-1.5 shrink-0 rounded-full px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-[0.12em]"
      style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary)" }}
    >
      {i18n("memberProgrammingMemberBadge")}
    </span>
  );
}
