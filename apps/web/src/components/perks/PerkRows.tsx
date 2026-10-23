"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { MemberPerk } from "@/api/perks";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

/** The partner's logo, or its initials on a quiet tile. */
export function PerkLogo({ name, url, size = 40 }: { name: string; url?: string | null; size?: number }) {
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

/**
 * The benefit in the member's words (`Palee.Perks.Benefit`): «−10% σε όλα τα
 * συμπληρώματα», «−15,00 €», «Δώρο: shaker», «Αγόρασε 2, πάρε 1», or the
 * gift; the API's English label is the fallback.
 */
export function useBenefitText() {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  return (perk: Pick<MemberPerk, "benefit" | "benefit_label">) => {
    const benefit = perk.benefit;
    const what = benefit?.text?.trim();
    const item = benefit?.item?.trim();
    switch (benefit?.type) {
      case "percent":
        if (benefit.percent) return what ? t("benefitPercentOn", { value: benefit.percent, what }) : t("benefitPercent", { value: benefit.percent });
        break;
      case "fixed_amount":
        if (benefit.amount_cents) {
          const amount = formatMinorUnits(locale, benefit.amount_cents, benefit.currency ?? "EUR");
          return what ? t("benefitAmountOn", { amount, what }) : t("benefitAmount", { amount });
        }
        break;
      case "free_item":
        if (item) return t("benefitFreeItem", { item });
        break;
      case "buy_x_get_y":
        if (benefit.buy_quantity && benefit.get_quantity) {
          const deal = t("benefitBuyGet", { buy: benefit.buy_quantity, get: benefit.get_quantity });
          return item ? `${deal} · ${item}` : deal;
        }
        break;
      case "free_text":
        if (what) return what;
        break;
    }
    return perk.benefit_label;
  };
}

/** The spend rules under the benefit: «Με αγορά από 30,00 €», «Έως 20,00 € έκπτωση». */
export function useBenefitConditions() {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  return (perk: Pick<MemberPerk, "benefit">) => {
    const { benefit } = perk;
    const currency = benefit?.currency ?? "EUR";
    return [
      benefit?.min_spend_cents ? t("benefitMinSpend", { amount: formatMinorUnits(locale, benefit.min_spend_cents, currency) }) : null,
      benefit?.type === "percent" && benefit.max_discount_cents ? t("benefitMaxDiscount", { amount: formatMinorUnits(locale, benefit.max_discount_cents, currency) }) : null,
    ].filter((line): line is string => Boolean(line));
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
