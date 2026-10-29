"use client";

import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { PerkLogo } from "./PerkRows";
import { usePerkCheck, useRedeemPerkCheck } from "./use-perks";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { formatClock } from "@/lib/clock";

function errorKey(error: unknown) {
  const code = error instanceof ApiError ? error.payload.code : null;
  if (code === "verification_link_expired") return "check.linkExpired";
  if (code === "perk_claim_already_used") return "check.alreadyUsed";
  return "check.invalid";
}

/**
 * What the partner's counter sees after scanning a member's Palee QR: the
 * perk, the box, valid or used, and one «Σημείωση ως χρησιμοποιημένο». No
 * account; the signed link is the credential and shows only the member's
 * first name and the short code under their QR.
 */
export function PerkCheckPage({ token }: { token: string }) {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  const check = usePerkCheck(token);
  const redeem = useRedeemPerkCheck(token);
  const data = check.data;
  const tone = data?.status === "valid" ? "var(--success)" : data?.status === "used" ? "var(--warning)" : "var(--danger)";

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-4 px-4 py-8" style={{ background: "var(--bg)" }}>
      <h1 className="text-center text-sm font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("check.title")}</h1>
      {data ? (
        <section className="flex flex-col items-center gap-3 rounded-3xl p-6 text-center" style={{ background: "var(--panel)", border: `2px solid ${tone}` }}>
          <PerkLogo name={data.business.name ?? data.perk.partner_name} url={data.business.logo_url} size={48} />
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("check.from", { box: data.business.name ?? "" })}</p>
          <p className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{data.perk.partner_name}</p>
          <p className="text-lg font-bold" style={{ color: "var(--text)" }}>{data.perk.benefit_label}</p>
          {data.code ? <p className="font-mono text-lg font-bold tracking-[0.1em]" style={{ color: "var(--text)" }}>{data.code}</p> : null}
          {data.member_first_name ? <p className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>{t("check.member", { name: data.member_first_name })}</p> : null}
          <p role="status" className="rounded-full px-4 py-1.5 text-base font-extrabold" style={{ background: `color-mix(in srgb, ${tone} 16%, var(--panel))`, color: tone }} data-testid="perk-check-status">
            {data.status === "used" && data.used_at
              ? t("check.usedAt", { date: formatClock(new Date(data.used_at), locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) })
              : t(`check.status_${data.status}`)}
          </p>
          {data.perk.valid_until ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("until", { date: formatDate(locale, data.perk.valid_until) })}</p> : null}
          {data.perk.terms ? <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text-soft)" }}>{data.perk.terms}</p> : null}
          {data.status === "valid" ? (
            <button
              type="button"
              onClick={() => redeem.mutate()}
              disabled={redeem.isPending}
              className="min-h-12 w-full rounded-2xl px-4 text-base font-bold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              data-testid="perk-check-redeem"
            >
              {redeem.isPending ? t("check.marking") : t("check.markUsed")}
            </button>
          ) : null}
          {redeem.isError ? <ErrorNotice>{t(errorKey(redeem.error))}</ErrorNotice> : null}
        </section>
      ) : check.isError ? (
        <ErrorNotice>
          {t(errorKey(check.error))}
        </ErrorNotice>
      ) : (
        <p className="text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      )}
      <p className="text-center text-xs" style={{ color: "var(--dim)" }}>{t("check.footer")}</p>
    </main>
  );
}
