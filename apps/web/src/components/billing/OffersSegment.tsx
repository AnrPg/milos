"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

import type { BillingProvider } from "@/api/my-billing";
import { formatDate, StatusBadge } from "@/components/finance/MembershipEntitlement";
import { HubCard } from "@/components/member-app/HubParts";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { PerkRows } from "@/components/perks/PerkRows";
import { useMemberPerks } from "@/components/perks/use-perks";
import { features } from "@/lib/features";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { Empty, Group, Row } from "./parts";

type T = ReturnType<typeof useTranslations<"Billing">>;

/**
 * Προσφορές, in this order: codes the box offers members, «Από συνεργάτες
 * του box» (partner perks, ADR-191, behind `features.partnerPerks`, read
 * from `/me/perks` rather than the billing slot), offers already claimed,
 * seasons joined, referral rewards with «Φέρε φίλο», trials. Empty groups
 * stay hidden; a wholly empty segment shows one line.
 */
export function OffersSegment({ provider, currency }: { provider: BillingProvider; currency: string }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const referrals = provider.referrals;
  const memberPerks = useMemberPerks(features.partnerPerks);
  const perks = (memberPerks.data ?? []).filter((perk) => perk.provider.organization_id === provider.organization_id);
  const hasReferrals = referrals.invited > 0 || referrals.credits.length > 0;
  const empty =
    provider.available_offers.length === 0 &&
    perks.length === 0 &&
    provider.promotions.length === 0 &&
    provider.seasons.length === 0 &&
    !hasReferrals &&
    provider.trials.length === 0;

  const inviteLink = (
    <Link
      href={`/me/referrals?box=${encodeURIComponent(provider.slug)}`}
      className="inline-flex min-h-11 items-center text-sm font-semibold"
      style={{ color: "var(--primary-strong)" }}
    >
      {t("inviteFriend")} ›
    </Link>
  );

  if (empty) {
    return (
      <div className="flex flex-col">
        <Empty>{t("noOffers")}</Empty>
        {inviteLink}
      </div>
    );
  }

  return (
    <HubCard>
      <div className="flex min-w-0 flex-col gap-5">
        {provider.available_offers.length > 0 ? (
          <Group title={t("availableTitle")}>
            {provider.available_offers.map((offer) => (
              <Row
                key={offer.id}
                title={offer.campaign_name ?? t("offer")}
                detail={[
                  discountText(t, locale, offer, currency),
                  offer.ends_on ? t("validUntil", { date: formatDate(locale, offer.ends_on) }) : null,
                ]
                  .filter(Boolean)
                  .join(" · ")}
                end={<CopyCode code={offer.code} />}
              />
            ))}
          </Group>
        ) : null}

        {perks.length > 0 ? (
          <Group title={t("perksTitle")}>
            <PerkRows perks={perks} />
          </Group>
        ) : null}

        {provider.promotions.length > 0 ? (
          <Group title={t("claimedTitle")}>
            {provider.promotions.map((promotion) => (
              <Row
                key={promotion.id}
                title={promotion.campaign_name ?? t("offer")}
                detail={promotion.redeemed_at ? formatDate(locale, promotion.redeemed_at) : null}
                end={<span className="text-sm font-semibold" style={{ color: "var(--success)" }}>{discountText(t, locale, promotion, currency)}</span>}
              />
            ))}
          </Group>
        ) : null}

        {provider.seasons.length > 0 ? (
          <Group title={t("seasonsTitle")}>
            {provider.seasons.map((season) => (
              <Row
                key={season.id}
                title={season.title}
                detail={`${formatDate(locale, season.starts_on)} – ${formatDate(locale, season.ends_on)}`}
                end={<StatusBadge status={season.status} />}
              />
            ))}
          </Group>
        ) : null}

        {hasReferrals ? (
          <Group title={t("referralsTitle")}>
            <li className="py-2.5 text-sm" style={{ color: "var(--text-soft)", borderBottom: "1px solid var(--border)" }}>
              {t("referralCounts", { invited: referrals.invited, paid: referrals.paid })}
              {referrals.credit_total_cents > 0 ? (
                <span className="block font-bold tabular-nums" style={{ color: "var(--success)" }}>
                  {t("rewardsTotal", { amount: formatMinorUnits(locale, referrals.credit_total_cents, currency) })}
                </span>
              ) : null}
            </li>
            {referrals.credits.map((credit) => (
              <Row
                key={credit.id}
                title={credit.description ?? t("referralReward")}
                detail={credit.occurred_on ? formatDate(locale, credit.occurred_on) : null}
                end={<span className="text-sm font-semibold tabular-nums">{formatMinorUnits(locale, credit.amount_cents, credit.currency)}</span>}
              />
            ))}
          </Group>
        ) : null}

        {provider.trials.length > 0 ? (
          <Group title={t("trialsTitle")}>
            {provider.trials.map((trial) => (
              <Row
                key={trial.id}
                title={trial.class_name ?? t("trial")}
                detail={trial.class_starts_at ? formatDate(locale, trial.class_starts_at) : null}
                end={<StatusBadge status={trial.status} />}
              />
            ))}
          </Group>
        ) : null}

        {inviteLink}
      </div>
    </HubCard>
  );
}

function CopyCode({ code }: { code: string }) {
  const t = useTranslations("Billing");
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <button
      type="button"
      onClick={() => void copy()}
      aria-label={t("copyCode", { code })}
      className="flex min-h-9 flex-col items-end"
    >
      <span className="font-mono text-sm font-bold" style={{ color: "var(--text)" }}>{code}</span>
      <span className="text-[11px] font-semibold" style={{ color: "var(--primary-strong)" }}>{copied ? t("copied") : t("copy")}</span>
    </button>
  );
}

function discountText(
  t: T,
  locale: string,
  offer: { discount_type?: string | null; discount_value?: number | null },
  currency: string,
) {
  const value = offer.discount_value;
  switch (offer.discount_type) {
    case "percent":
      return value == null ? t("discount") : `−${value}%`;
    case "fixed_amount":
      return value == null ? t("discount") : `−${formatMinorUnits(locale, value, currency)}`;
    case "free_period":
      return t("freePeriod");
    default:
      return t("discount");
  }
}
