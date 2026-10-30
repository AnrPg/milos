"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { HubCard } from "@/components/member-app/HubParts";

import { PartnerIcon } from "./PartnerBits";
import { PARTNERS_HREF, nearbyCard, partnersStage } from "./partners-model";
import { usePartnerDeck, usePartnersOverview } from "./use-partners";

/**
 * Γύρω μου › «Συναθλητές κοντά σου» (ADR-280, mockup decision 1 A): the one
 * way into the public deck. Once I'm in, how many people are near me and
 * the time most of them share with me; before that, one card to start.
 * Hidden whenever there is nothing to offer (vision §4.2).
 */
export function PartnersNearbyCard() {
  const t = useTranslations("Partners");
  const overview = usePartnersOverview();
  const inDeck = overview.data?.eligibility ? partnersStage(overview.data) === "deck" : false;
  // The same request as the deck without filters, so opening it is instant.
  const deck = usePartnerDeck({}, inDeck);
  const card = nearbyCard(overview.data, inDeck ? deck.data : undefined);
  if (card.kind === "hidden") return null;

  return (
    <HubCard highlighted={card.kind === "start"}>
      <Link href={PARTNERS_HREF} className="flex items-center gap-3" data-testid="partners-nearby">
        <span
          className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl"
          style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", color: "var(--primary)" }}
        >
          <PartnerIcon name="people" size={24} />
        </span>
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="text-base font-extrabold" style={{ color: "var(--text)" }}>{t("nearbyTitle")}</span>
          {card.kind === "people" ? (
            <>
              <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                {card.more ? t("nearbyCountMore", { count: card.count }) : t("nearbyCount", { count: card.count })}
              </span>
              {card.time ? (
                <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                  {t("nearbyTime", { count: card.timeCount, time: t(`time_${card.time}`) })}
                </span>
              ) : null}
              {overview.data?.distance === "available" && deck.data ? (
                <span className="text-xs" style={{ color: "var(--dim)" }}>{t("withinKm", { km: deck.data.within_km })}</span>
              ) : null}
            </>
          ) : (
            <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("nearbyStart")}</span>
          )}
        </span>
        <span
          className="shrink-0 rounded-full px-3 py-1.5 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {card.kind === "people" ? t("nearbyOpen") : t("nearbyStartCta")}
        </span>
      </Link>
    </HubCard>
  );
}
