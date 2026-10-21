"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPublicPlans, startCoachPractice } from "@/api/platform-plans";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { rememberSelectedOrganization } from "@/lib/organization-slug";
import { defaultTeamName, ownsCoachPractice, shownMonthlyPrice } from "@/lib/solo-coach";
import { setView } from "@/lib/view-mode";

/**
 * ADR-170 (vision §7.10): one screen to open a practice as an independent
 * coach. Name, the «Team» club's name, what the plan includes and its trial;
 * a price shows only once the platform has confirmed it. Creating it lands
 * the coach in their console, where the coach checklist takes over.
 */
export function StartCoachPractice() {
  const t = useTranslations("SoloCoach");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const { memberships } = useSelectedMembershipRole();
  const [name, setName] = useState("");
  const [teamName, setTeamName] = useState<string | null>(null);
  const plans = useQuery({ queryKey: ["public", "platform-plans", "coach"], queryFn: () => fetchPublicPlans("coach") });
  const plan = plans.data?.plans.find((entry) => entry.is_default) ?? plans.data?.plans[0] ?? null;
  const price = shownMonthlyPrice(plan, locale);
  const team = teamName ?? (name.trim() ? defaultTeamName(name) : "");

  const create = useMutation({
    mutationFn: () =>
      startCoachPractice(tokens!.access_token, {
        name: name.trim(),
        team_name: team.trim() || null,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        default_locale: locale,
      }),
    onSuccess: (practice) => {
      rememberSelectedOrganization(practice.slug);
      setView("staff");
      queryClient.clear();
      router.push(`/org/${practice.slug}/admin`);
    },
  });

  function submit(event: FormEvent) {
    event.preventDefault();
    if (name.trim().length < 2 || !tokens?.access_token) return;
    create.mutate();
  }

  if (ownsCoachPractice(memberships)) {
    return (
      <HubPage title={t("start.title")}>
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("start.alreadyOpen")}</p>
        </HubCard>
      </HubPage>
    );
  }

  return (
    <HubPage title={t("start.title")}>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("start.intro")}</p>

      <HubCard eyebrow={t("start.includes")}>
        <ul className="flex flex-col gap-2 text-sm" style={{ color: "var(--text)" }}>
          {(["clients", "sessions", "team", "bootcamps"] as const).map((item) => (
            <li key={item} className="flex gap-2">
              <span aria-hidden="true" style={{ color: "var(--primary-strong)" }}>✓</span>
              {t(`start.include.${item}`)}
            </li>
          ))}
        </ul>
        {plan ? (
          <p className="mt-4 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {[
              plan.trial_days > 0 ? t("start.trial", { days: plan.trial_days }) : null,
              price ? t("start.price", { price }) : t("start.priceSoon"),
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
        ) : null}
      </HubCard>

      <form onSubmit={submit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("start.nameLabel")}</span>
          <input
            value={name}
            onChange={(event) => setName(event.target.value)}
            required
            minLength={2}
            maxLength={120}
            autoComplete="name"
            placeholder={t("start.namePlaceholder")}
            className="min-h-11 rounded-2xl px-4 text-base"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("start.nameHint")}</span>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("start.teamLabel")}</span>
          <input
            value={team}
            onChange={(event) => setTeamName(event.target.value)}
            maxLength={80}
            className="min-h-11 rounded-2xl px-4 text-base"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("start.teamHint")}</span>
        </label>
        {create.error ? (
          <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(create.error, i18n)}</p>
        ) : null}
        <button
          type="submit"
          disabled={create.isPending || name.trim().length < 2}
          className="min-h-12 rounded-2xl px-4 text-base font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {create.isPending ? t("start.creating") : t("start.submit")}
        </button>
      </form>
    </HubPage>
  );
}
