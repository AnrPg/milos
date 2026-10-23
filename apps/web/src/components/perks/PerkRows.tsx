"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { MemberPerk, PerkCommon } from "@/api/perks";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

/** The partner's logo, or its initials on a quiet tile. */
export function PerkLogo({ name, url, size = 40 }: { name: string; url: string | null; size?: number }) {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toLocaleUpperCase())
    .join("");
  return (
    <span
      className="inline-flex shrink-0 items-center justify-center overflow-hidden rounded-2xl text-sm font-extrabold"
      style={{ width: size, height: size, background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
    >
      {url ? (
        // eslint-disable-next-line @next/next/no-img-element -- the box's media
        <img src={url} alt="" className="h-full w-full object-cover" />
      ) : (
        <span aria-hidden="true">{initials}</span>
      )}
    </span>
  );
}

/** The benefit in the member's words: «−10% σε όλα τα συμπληρώματα», «−15,00 €», or the gift. */
export function useBenefitText() {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  return (perk: Pick<PerkCommon, "benefit_type" | "benefit_value" | "benefit_text" | "benefit_label" | "currency">) => {
    const what = perk.benefit_text?.trim();
    if (perk.benefit_type === "percent" && perk.benefit_value !== null) {
      return what ? t("benefitPercentOn", { value: perk.benefit_value, what }) : t("benefitPercent", { value: perk.benefit_value });
    }
    if (perk.benefit_type === "fixed_amount" && perk.benefit_value !== null) {
      const amount = formatMinorUnits(locale, perk.benefit_value, perk.currency);
      return what ? t("benefitAmountOn", { amount, what }) : t("benefitAmount", { amount });
    }
    return what || perk.benefit_label;
  };
}

/** «Από συνεργάτες του box» in Πληρωμές › Προσφορές: one row per perk, opening its page. */
export function PerkRows({ perks }: { perks: MemberPerk[] }) {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  const benefit = useBenefitText();
  return (
    <>
      {perks.map((perk) => {
        const until = perk.valid_until ? t("until", { date: formatDate(locale, perk.valid_until) }) : t("noEnd");
        const used = perk.claim?.status === "used";
        return (
          <li key={perk.id} style={{ borderBottom: "1px solid var(--border)" }}>
            <Link href={`/me/payments/perks/${encodeURIComponent(perk.id)}`} className="flex min-w-0 items-center gap-3 py-2.5" data-testid="billing-perk-row">
              <PerkLogo name={perk.partner_name} url={perk.logo_url} />
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{perk.partner_name}</span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>{[benefit(perk), until].join(" · ")}</span>
              </span>
              <span className="shrink-0 rounded-xl px-3 py-1.5 text-xs font-bold" style={{ border: "1px solid var(--border)", color: used ? "var(--dim)" : "var(--primary-strong)" }}>
                {used ? t("usedShort") : perk.claim ? t("open") : t(`cta_${perk.redemption_method}`)}
              </span>
            </Link>
          </li>
        );
      })}
    </>
  );
}
