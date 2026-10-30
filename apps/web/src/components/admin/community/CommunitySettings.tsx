"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchStaffGroups,
  MEMBER_GROUP_OPTIONS,
  STAFF_GROUPS_KEY,
  updateCommunitySettings,
  type MemberGroupsSetting as Setting,
} from "@/api/admin-community";
import { clientErrorMessage } from "@/components/client/errors";
import { ChoicePill, ErrorLine } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/** Ομάδες μελών: Όχι · Με έγκριση (default) · Ελεύθερα (plan D6, board 7 Q3). Saves on pick. */
export function MemberGroupsSetting({ current }: { current: Setting }) {
  const t = useTranslations("CommunityAdmin");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const save = useMutation({
    mutationFn: (value: Setting) => updateCommunitySettings(tokens!.access_token, { member_groups: value }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: STAFF_GROUPS_KEY }),
  });
  const value = save.isPending && save.variables ? save.variables : current;

  return (
    <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <h2 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("settingTitle")}</h2>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("settingHint")}</p>
      <div role="radiogroup" aria-label={t("settingTitle")} className="flex flex-col gap-2 sm:flex-row">
        {MEMBER_GROUP_OPTIONS.map((option) => (
          <ChoicePill key={option} selected={value === option} onSelect={() => save.mutate(option)} hint={t(`setting_${option}_hint`)}>
            {t(`setting_${option}`)}
          </ChoicePill>
        ))}
      </div>
      <ErrorLine message={save.error ? clientErrorMessage(save.error, tUi) : null} />
    </section>
  );
}

/** The settings entry for «Κοινότητα»: the member-groups setting, and a link to the staff page. */
export function CommunitySettingsLink() {
  const t = useTranslations("CommunityAdmin");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const groups = useQuery({ queryKey: STAFF_GROUPS_KEY, enabled: Boolean(token), queryFn: () => fetchStaffGroups(token) });

  return (
    <div className="flex flex-col gap-3">
      {/* An answer without settings shows only the link instead of crashing the hub. */}
      {groups.data?.settings ? <MemberGroupsSetting current={groups.data.settings.member_groups} /> : null}
      <Link
        href={adminHref("/admin/community", slug)}
        className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      >
        <span className="flex flex-col">
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("title")}</span>
          <span className="text-sm" style={{ color: "var(--muted)" }}>{t("settingsNavHint")}</span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </Link>
    </div>
  );
}
