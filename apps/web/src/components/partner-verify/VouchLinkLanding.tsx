"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { VOUCHING_KEY, fetchVouching, inspectVouchLink, vouchByLink } from "@/api/partner-verification";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { BackLink } from "@/components/ui/BackLink";

import { VouchingStanding } from "./VouchRequestsPage";
import { VerifyCard, VerifyError, VerifyIcon, primaryButton, primaryStyle, secondaryStyle } from "./verify-ui";

/** The token of a sponsor link: `/partners/vouch#token=…` (a fragment never reaches a server log). */
export function linkTokenFromHash(hash: string) {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  return params.get("token")?.trim() || null;
}

/**
 * Where a sponsor link or QR lands (ADR-280 §2): who it is for and whether
 * you may vouch (inspect), what vouching means, then «Εγγυώμαι». Single use,
 * 10 minutes.
 */
export function VouchLinkLanding() {
  const t = useTranslations("PartnerVerify");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [linkToken, setLinkToken] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    const read = () => setLinkToken(linkTokenFromHash(window.location.hash));
    read();
    window.addEventListener("hashchange", read);
    return () => window.removeEventListener("hashchange", read);
  }, []);
  const inspection = useQuery({
    queryKey: ["my", "partners", "vouch-link", linkToken],
    enabled: Boolean(token && linkToken),
    queryFn: () => inspectVouchLink(token!, linkToken!),
    retry: false,
    staleTime: Infinity,
  });
  const vouch = useMutation({ mutationFn: () => vouchByLink(token!, linkToken!) });
  const data = inspection.data;
  // Why you may not vouch now, with the date a pause ends.
  const vouching = useQuery({
    queryKey: VOUCHING_KEY,
    enabled: Boolean(token && data && !data.can_vouch),
    queryFn: () => fetchVouching(token!),
  });
  const name = data?.person.nickname ?? t("someone");

  return (
    <div className="flex min-w-0 flex-col gap-4" data-testid="vouch-link">
      <header className="flex flex-col gap-1">
        <BackLink href="/partners" className="self-start text-sm font-semibold">{t("back")}</BackLink>
        <h1 className="text-2xl font-bold" style={{ color: "var(--text)" }}>{t("vouchLink.title")}</h1>
      </header>
      {linkToken === null ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("vouchLink.missing")}</p> : null}
      {inspection.isFetching ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("loading")}</p> : null}
      {inspection.error ? <VerifyError error={inspection.error} /> : null}
      {data ? (
        <VerifyCard>
          <div className="flex min-w-0 items-center gap-3">
            <PersonAvatar name={data.person.nickname} url={data.person.avatar_url} size={48} />
            <div className="min-w-0">
              <p className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("vouch.asks", { name })}</p>
              <p className="text-xs" style={{ color: "var(--dim)" }}>{t("vouch.forPartners")}</p>
            </div>
          </div>
          {vouch.isSuccess ? (
            <p role="status" className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--success)" }}>
              <VerifyIcon name="check" /> {t("vouch.didVouch", { name })}
            </p>
          ) : data.can_vouch ? (
            <>
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("vouch.meaningLink")}</p>
              <VerifyError error={vouch.error} />
              <div className="flex flex-wrap gap-2">
                <button type="button" className={primaryButton} style={primaryStyle} disabled={vouch.isPending} onClick={() => vouch.mutate()}>
                  <VerifyIcon name="shield" /> {t("vouch.vouch")}
                </button>
                <Link href="/partners" className={primaryButton} style={secondaryStyle}>{t("vouch.decline")}</Link>
              </div>
            </>
          ) : (
            <>
              <p className="text-sm" style={{ color: "var(--warning)" }}>{t(`error.${data.reason ?? "partner_sponsor_not_eligible"}`)}</p>
              {vouching.data ? <VouchingStanding vouching={vouching.data} /> : null}
            </>
          )}
        </VerifyCard>
      ) : null}
    </div>
  );
}
