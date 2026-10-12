"use client";

import { useTranslations } from "next-intl";

import { useSelectedMembershipRole } from "@/lib/membership-role";

export const PERSONAL_PR_GYM = "";

export type PRGymOption = { slug: string; name: string };

/**
 * ADR-119: the gyms a new PR can be recorded in and the default choice (the
 * selected gym when the caller belongs to it, else "personal").
 */
export function usePRGymOptions(): { gyms: PRGymOption[]; defaultGymSlug: string } {
  const { memberships, selectedOrganizationSlug } = useSelectedMembershipRole();
  const gyms = memberships.map(({ organization }) => ({ slug: organization.slug, name: organization.name }));

  return { gyms, defaultGymSlug: defaultPRGymSlug(gyms, selectedOrganizationSlug) };
}

export function defaultPRGymSlug(gyms: PRGymOption[], selectedSlug: string | null) {
  return selectedSlug && gyms.some((gym) => gym.slug === selectedSlug) ? selectedSlug : PERSONAL_PR_GYM;
}

/** The `organization_slug` a new PR is submitted with; null records a personal PR. */
export function prGymSlugForSubmit(slug: string) {
  return slug === PERSONAL_PR_GYM ? null : slug;
}

/**
 * Where a new PR was set. Choosing a gym records it as the PR's organization
 * provenance, which makes it visible to that gym's coaches (unless the owner
 * opted out); "personal" keeps it private.
 */
export function PRGymField({
  gyms,
  value,
  onChange,
}: {
  gyms: PRGymOption[];
  value: string;
  onChange: (slug: string) => void;
}) {
  const t = useTranslations("PrSharing");

  if (gyms.length === 0) return null;

  return (
    <div className="space-y-1.5">
      <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
        {t("gymLabel")}
        <select
          className="mt-1.5 w-full rounded-xl px-4 py-2.5 text-sm normal-case tracking-normal outline-none"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        >
          {gyms.map((gym) => (
            <option key={gym.slug} value={gym.slug}>{gym.name}</option>
          ))}
          <option value={PERSONAL_PR_GYM}>{t("gymPersonal")}</option>
        </select>
      </label>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("gymHint")}</p>
    </div>
  );
}
