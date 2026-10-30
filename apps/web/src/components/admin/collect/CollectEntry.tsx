"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { Card, formatMoney } from "@/components/fiscal/fiscal-ui";
import { formatTime } from "@/components/client/format";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { nativePlatform } from "@/lib/platform";


import { BigLink, CollectIcon } from "./collect-ui";
import { cardTotalCents } from "./collect-flow";
import { useRecoveredPayment, useTapToPaySupported, useTerminalAppInstalled, useTerminalAvailability } from "./use-collect";

// Where the «Viva.com Terminal» app is found (a store search: the listing
// differs by country).
const STORE_URL = {
  android: "https://play.google.com/store/search?q=Viva.com%20Terminal&c=apps",
  ios: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=Viva.com%20Terminal",
} as const;

/**
 * «Είσπραξη» on the staff home (mockup pilot-gaps screen 2 A, the home
 * page): the big button, or why Tap to Pay cannot run on this phone, and a
 * payment that came back from Viva after iOS reset the app.
 */
export function CollectEntry() {
  const supported = useTapToPaySupported();
  if (!supported) return null;
  return <CollectEntryOnPhone />;
}

function CollectEntryOnPhone() {
  const t = useTranslations("Collect");
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const availability = useTerminalAvailability();
  const installed = useTerminalAppInstalled(true);
  const recovered = useRecoveredPayment(true);
  const platform = nativePlatform();

  if (availability.isPending) return null;

  const reason = availability.data && !availability.data.available ? availability.data.reason ?? "no_viva" : null;

  return (
    <div className="grid gap-3 px-4 pt-4 md:px-10" data-testid="collect-entry">
      {recovered ? (
        <Link
          href={adminHref(`/admin/collect?payment=${recovered.id}`, slug)}
          className="flex items-center gap-3 rounded-[18px] px-4 py-3"
          style={{ background: "color-mix(in srgb, var(--primary) 10%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
          data-testid="collect-recovered"
        >
          <CollectIcon name="nfc" size={20} />
          <span className="grid min-w-0 flex-1">
            <b className="text-sm">{t("recoveredTitle")}</b>
            <span className="truncate text-xs" style={{ color: "var(--muted)" }}>
              {[recovered.description, formatMoney(locale, cardTotalCents(recovered), recovered.currency), recovered.inserted_at ? formatTime(recovered.inserted_at, locale) : null]
                .filter(Boolean)
                .join(" · ")}
            </span>
          </span>
          <CollectIcon name="chevron" size={16} />
        </Link>
      ) : null}

      {availability.isError ? null : reason ? (
        <Card testId="collect-unavailable">
          <div className="flex items-start gap-3">
            <span style={{ color: "var(--primary-strong)" }}>
              <CollectIcon name="nfc" size={22} />
            </span>
            <div className="grid min-w-0 gap-1">
              <b className="text-sm" style={{ color: "var(--text)" }}>{t("unavailableTitle")}</b>
              <span className="text-xs" style={{ color: "var(--muted)" }}>{t(`reason_${reason}`)}</span>
            </div>
          </div>
          <BigLink href={adminHref("/admin/settings?tab=payments", slug)} ghost>
            {t("paymentSettings")}
          </BigLink>
        </Card>
      ) : installed === false ? (
        <Card testId="collect-no-app">
          <div className="flex items-start gap-3">
            <span style={{ color: "var(--primary-strong)" }}>
              <CollectIcon name="plus" size={22} />
            </span>
            <div className="grid min-w-0 gap-1">
              <b className="text-sm" style={{ color: "var(--text)" }}>{t("noAppTitle")}</b>
              <span className="text-xs" style={{ color: "var(--muted)" }}>{t("noAppBody")}</span>
            </div>
          </div>
          <a
            href={STORE_URL[platform ?? "android"]}
            className="flex min-h-12 w-full items-center justify-center rounded-2xl px-4 text-base font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("openStore")}
          </a>
        </Card>
      ) : (
        <BigLink href={adminHref("/admin/collect", slug)} testId="collect-start">
          <CollectIcon name="nfc" />
          {t("title")}
        </BigLink>
      )}
    </div>
  );
}
