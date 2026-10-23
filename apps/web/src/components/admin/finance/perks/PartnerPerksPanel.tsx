"use client";

import { useTranslations } from "next-intl";
import { useState } from "react";

import type { StaffPerk } from "@/api/perks";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { PerkLogo, useBenefitText } from "@/components/perks/PerkRows";
import { useStaffPerks } from "@/components/perks/use-perks";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { SPARK_CREATE_STYLE } from "@/lib/spark";
import { codesHandedOut, localToday, perkPhase } from "@/lib/perks/validity";

import { PerkForm } from "./PerkForm";

const PHASE_TONE: Record<string, string> = {
  published: "var(--success)",
  scheduled: "var(--info)",
  paused: "var(--warning)",
  draft: "var(--dim)",
  expired: "var(--dim)",
};

/**
 * Οικονομικά › Προσφορές › Συνεργατών (ADR-191): the box's partner perks
 * with how many members claimed the code and how many used it, and for a
 * pool of unique codes how many were handed out. A row opens the form.
 * Partner perks never appear in Γύρω μου: only the box's clients see them.
 */
export function PartnerPerksPanel() {
  const t = useTranslations("PerksAdmin");
  const locale = useUiLocale();
  const benefit = useBenefitText();
  const perks = useStaffPerks();
  const [open, setOpen] = useState<StaffPerk | "new" | null>(null);
  const today = localToday();
  const list = perks.data ?? [];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{t("listTitle", { count: list.length })}</p>
        <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={SPARK_CREATE_STYLE} onClick={() => setOpen("new")} data-testid="perk-new">
          {t("new")}
        </button>
      </div>

      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {perks.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : perks.isError ? (
          <p role="alert" className="px-6 py-8 text-sm" style={{ color: "var(--danger)" }}>{t("loadFailed")}</p>
        ) : list.length === 0 ? (
          <div className="flex flex-col gap-1 px-6 py-8">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("emptyTitle")}</p>
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("emptyBody")}</p>
          </div>
        ) : (
          list.map((perk, index) => {
            const phase = perkPhase(perk, today);
            const meta = [
              t(`method_${perk.redemption_method}`) + (perk.shared_code ? ` ${perk.shared_code}` : ""),
              perk.audience === "packages" ? t("sum_packages", { count: perk.package_ids.length }) : t("audience_all_clients"),
              perk.valid_until ? t("until", { date: formatDate(locale, perk.valid_until) }) : t("noEnd"),
            ];
            return (
              <button
                key={perk.id}
                type="button"
                onClick={() => setOpen(perk)}
                className="flex w-full flex-col gap-2 px-5 py-4 text-start transition-opacity hover:opacity-80 sm:flex-row sm:items-center"
                style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}
                data-testid="perk-row"
              >
                <span className="flex min-w-0 flex-1 items-center gap-3">
                  <PerkLogo name={perk.partner_name} url={perk.logo_url} />
                  <span className="flex min-w-0 flex-col">
                    <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{perk.partner_name} · {benefit(perk)}</span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>{meta.join(" · ")}</span>
                    <span className="text-xs font-semibold tabular-nums" style={{ color: "var(--text-soft)" }}>
                      {t("stats", { claims: perk.claims_count, uses: perk.uses_count })}
                      {perk.codes ? ` · ${t("codesStat", { handed: codesHandedOut(perk.codes), total: perk.codes.total })}` : ""}
                    </span>
                  </span>
                </span>
                <span className="flex shrink-0 items-center gap-2">
                  {perk.box_benefits ? (
                    <span className="rounded-full px-2.5 py-1 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>{t("partnership")}</span>
                  ) : null}
                  <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: `color-mix(in srgb, ${PHASE_TONE[phase]} 14%, var(--panel))`, color: PHASE_TONE[phase] }}>
                    {t(`status_${phase}`)}
                  </span>
                </span>
              </button>
            );
          })
        )}
      </div>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("listNote")}</p>

      {open ? <PerkForm perk={open === "new" ? null : open} onClose={() => setOpen(null)} /> : null}
    </div>
  );
}
