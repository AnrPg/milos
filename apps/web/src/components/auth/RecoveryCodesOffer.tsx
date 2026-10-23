"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";

export const RECOVERY_CODES_HREF = "/me/settings#recovery-codes";

/**
 * ADR-187: right after sign-up, offer recovery codes once. Optional: "Not now"
 * carries on to where the person was going.
 */
export function RecoveryCodesOffer({ onSkip }: { onSkip: () => void }) {
  const t = useTranslations("authRecovery");

  return (
    <section className="space-y-4 text-center" aria-labelledby="recovery-offer-title">
      <h2 id="recovery-offer-title" className="text-lg font-semibold" style={{ color: "var(--text)" }}>
        {t("accountCreatedTitle")}
      </h2>
      <div
        className="rounded-2xl px-4 py-4 text-start text-sm leading-6"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      >
        <p className="font-semibold" style={{ color: "var(--text)" }}>
          {t("recoveryOfferTitle")}
        </p>
        <p className="mt-1">{t("recoveryOfferBody")}</p>
      </div>
      <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href={RECOVERY_CODES_HREF}>
        {t("recoveryOfferAction")}
      </Link>
      <button type="button" className="text-sm font-semibold" style={{ color: "var(--dim)" }} onClick={onSkip}>
        {t("recoveryOfferSkip")}
      </button>
    </section>
  );
}
