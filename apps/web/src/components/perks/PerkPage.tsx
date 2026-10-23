"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

import { ApiError } from "@/api/client";
import type { MemberPerk, PerkClaim } from "@/api/perks";
import { QrCode } from "@/components/check-in/QrCode";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { PerkLogo, useBenefitConditions, useBenefitText } from "./PerkRows";
import { useClaimPerk, useMemberPerks, useRefreshPerkLink } from "./use-perks";

const REASONS = new Set([
  "perk_sold_out",
  "perk_period_sold_out",
  "perk_member_limit",
  "perk_member_period_limit",
  "perk_outside_hours",
  "perk_not_available",
  "perk_codes_exhausted",
]);

function reasonKey(code: string | null | undefined) {
  return code && REASONS.has(code) ? `reason_${code}` : "reason_other";
}

/**
 * A partner perk (Εγώ › Πληρωμές › Προσφορές › συνεργάτης): who and what,
 * then the way this partner redeems it: a code with Αντιγραφή and «Δείξε
 * QR» (shared, from the pool, or applied by the partner's link), a personal
 * Palee QR the store scans, or «Δείξε τη συνδρομή σου». The code is only
 * handed out when the member claims it. Terms and the address close the page.
 */
export function PerkPage({ perkId }: { perkId: string }) {
  const t = useTranslations("Perks");
  const perks = useMemberPerks();
  const perk = perks.data?.find((item) => item.id === perkId) ?? null;
  const backHref = perk?.provider.slug ? `/me/payments?box=${encodeURIComponent(perk.provider.slug)}&tab=offers` : "/me/payments";

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <Link href={backHref} className="inline-flex min-h-9 items-center self-start text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
        ‹ {t("back")}
      </Link>
      {perk ? (
        <PerkBody perk={perk} />
      ) : perks.isLoading ? (
        <p className="py-8 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : (
        <p role="alert" className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {t("missing")}
        </p>
      )}
    </main>
  );
}

function PerkBody({ perk }: { perk: MemberPerk }) {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  const benefit = useBenefitText();
  const conditions = useBenefitConditions()(perk);
  const claim = useClaimPerk();
  const current = perk.claim;
  const until = perk.valid_until ? t("until", { date: formatDate(locale, perk.valid_until) }) : t("noEnd");

  return (
    <>
      <section className="flex flex-col items-center gap-2 rounded-3xl p-5 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <PerkLogo name={perk.partner_name} url={perk.logo_url} size={56} />
        <h1 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{perk.partner_name}</h1>
        <p className="text-lg font-bold" style={{ color: "var(--text)" }}>{benefit(perk)}</p>
        {conditions.length > 0 ? <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{conditions.join(" · ")}</p> : null}
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t("forMembersOf", { box: perk.provider.name ?? "" })} · {until}
        </p>
      </section>

      {current ? (
        <Redeem perk={perk} claim={current} />
      ) : (
        <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`how_${perk.redemption_method}`)}</p>
          {perk.claimable ? (
            <button
              type="button"
              onClick={() => claim.mutate(perk.id)}
              disabled={claim.isPending}
              className="min-h-12 rounded-2xl px-4 text-base font-bold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              data-testid="perk-claim"
            >
              {claim.isPending ? t("claiming") : t(`claim_${perk.redemption_method}`)}
            </button>
          ) : (
            <p className="text-sm font-semibold" style={{ color: "var(--warning)" }}>{t(reasonKey(perk.unavailable_reason))}</p>
          )}
          {claim.isError ? (
            <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
              {t(reasonKey(claim.error instanceof ApiError ? claim.error.payload.code : null))}
            </p>
          ) : null}
        </section>
      )}

      {perk.terms ? (
        <section className="flex flex-col gap-1 rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("terms")}</p>
          <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text-soft)" }}>{perk.terms}</p>
        </section>
      ) : null}

      {perk.partner_address ? (
        <a
          href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(perk.partner_address)}`}
          target="_blank"
          rel="noreferrer"
          className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-4 text-sm font-semibold"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          <span className="truncate">{perk.partner_address}</span>
          <span style={{ color: "var(--primary-strong)" }}>{t("directions")} ›</span>
        </a>
      ) : null}

    </>
  );
}

function Redeem({ perk, claim }: { perk: MemberPerk; claim: PerkClaim }) {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  const [showQr, setShowQr] = useState(false);

  if (claim.status === "used" || claim.status === "revoked") {
    return (
      <section className="rounded-3xl p-5 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <p className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
          {claim.status === "used" ? t("usedOn", { date: formatDate(locale, claim.used_at ?? claim.claimed_at) }) : t("revoked")}
        </p>
      </section>
    );
  }

  const instructions = claim.instructions ?? perk.instructions;
  const note = instructions ? <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text)" }}>{instructions}</p> : null;

  if (perk.redemption_method === "personal_qr") return <PaleeQr claim={claim} note={note} />;
  if (perk.redemption_method === "show_membership" || claim.show_membership) return <ShowMembership perk={perk} note={note} />;

  const code = claim.code ?? "";
  const method = perk.redemption_method;
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {code ? (
        <>
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {method === "code_pool" ? t("yourCode") : t("code")}
          </p>
          <p className="rounded-2xl px-4 py-3 text-center font-mono text-2xl font-extrabold tracking-[0.12em]" style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px dashed var(--border)" }} data-testid="perk-code">
            {code}
          </p>
          <div className="grid grid-cols-2 gap-2">
            <CopyButton code={code} />
            <button type="button" onClick={() => setShowQr(true)} className="min-h-11 rounded-2xl px-3 text-sm font-bold" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("showQr")}
            </button>
          </div>
        </>
      ) : null}
      {method === "partner_link" && (claim.url ?? claim.partner_url) ? (
        <a href={claim.url ?? claim.partner_url ?? undefined} target="_blank" rel="noreferrer" className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} data-testid="perk-partner-link">
          {t("openPartnerLink")}
        </a>
      ) : null}
      {note}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t(method === "partner_link" ? (code ? "hint_partner_link" : "hint_partner_link_only") : method === "code_pool" ? "hint_code_pool" : "hint_shared_code")}</p>
      {showQr ? (
        <QrDialog value={code} title={perk.partner_name} caption={code} onClose={() => setShowQr(false)} />
      ) : null}
    </section>
  );
}

/** A personal Palee QR: the store scans it and opens the signed link; the API signs a new one each time it is shown. */
function PaleeQr({ claim, note }: { claim: PerkClaim; note: React.ReactNode }) {
  const t = useTranslations("Perks");
  const refresh = useRefreshPerkLink();
  const link = claim.verification;
  const { mutate } = refresh;
  const expiresAt = link?.expires_at ?? null;

  useEffect(() => {
    if (!expiresAt || new Date(expiresAt).getTime() <= Date.now()) mutate(claim.id);
  }, [claim.id, mutate, expiresAt]);

  const url = link && typeof window !== "undefined" ? new URL(link.path, window.location.origin).toString() : null;
  return (
    <section className="flex flex-col items-center gap-3 rounded-3xl p-5 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="w-full max-w-[16rem] rounded-3xl p-3" style={{ background: "var(--paper)" }}>
        {url ? (
          <QrCode value={url} label={t("qrLabel")} testId="perk-qr" className="aspect-square w-full" />
        ) : (
          <div className="flex aspect-square w-full items-center justify-center text-sm" style={{ color: "var(--on-paper)", opacity: 0.7 }}>
            {refresh.isError ? t("qrFailed") : t("loading")}
          </div>
        )}
      </div>
      {claim.code ? <p className="font-mono text-lg font-bold tracking-[0.1em]" style={{ color: "var(--text)" }}>{claim.code}</p> : null}
      {note}
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("hint_personal_qr")}</p>
      <button type="button" onClick={() => refresh.mutate(claim.id)} disabled={refresh.isPending} className="min-h-11 text-sm font-bold disabled:opacity-50" style={{ color: "var(--primary-strong)" }}>
        {t("newQr")}
      </button>
    </section>
  );
}

/** «Δείξε τη συνδρομή σου»: a live card (the clock keeps moving, so a screenshot shows). */
function ShowMembership({ perk, note }: { perk: MemberPerk; note: React.ReactNode }) {
  const t = useTranslations("Perks");
  const locale = useUiLocale();
  const { currentUser } = useSession();
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(timer);
  }, []);
  const name = (currentUser as { nickname?: string | null } | null)?.nickname ?? "";
  return (
    <section className="flex flex-col items-center gap-2 rounded-3xl p-5 text-center" style={{ background: "color-mix(in srgb, var(--primary) 12%, var(--panel))", border: "1px solid var(--primary)" }} data-testid="perk-membership">
      <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("membershipCard")}</p>
      <p className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{name}</p>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("memberOf", { box: perk.provider.name ?? "" })}</p>
      <p className="font-mono text-lg tabular-nums" style={{ color: "var(--text)" }}>{now.toLocaleString(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit" })}</p>
      {note}
      <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("hint_show_membership")}</p>
    </section>
  );
}

function CopyButton({ code }: { code: string }) {
  const t = useTranslations("Perks");
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
    <button type="button" onClick={() => void copy()} className="min-h-11 rounded-2xl px-3 text-sm font-bold" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }} aria-live="polite">
      {copied ? t("copied") : t("copy")}
    </button>
  );
}

/** «Δείξε QR»: the code as a themed QR, large, on the modal layer (the bottom bar steps aside). */
function QrDialog({ value, title, caption, onClose }: { value: string; title: string; caption: string; onClose: () => void }) {
  const t = useTranslations("Perks");
  return (
    <Dialog onClose={onClose} title={title} variant="center" size="sm" layer="fullscreen">
      <div className="flex flex-col items-center gap-3 pb-2">
        <div className="w-full max-w-[18rem] rounded-3xl p-3" style={{ background: "var(--paper)" }}>
          <QrCode value={value} label={t("qrOfCode", { code: caption })} testId="perk-code-qr" className="aspect-square w-full" />
        </div>
        <p className="font-mono text-lg font-bold tracking-[0.1em]" style={{ color: "var(--text)" }}>{caption}</p>
      </div>
    </Dialog>
  );
}
