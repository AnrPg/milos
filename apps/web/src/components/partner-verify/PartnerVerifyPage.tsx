"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  VERIFICATION_KEY,
  fetchVerification,
  giveConsent,
  withdrawVerification,
  type VerificationOverview,
  type VerificationRequest,
} from "@/api/partner-verification";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";

import { PhoneStep } from "./PhoneStep";
import { SelfieStep } from "./SelfieStep";
import { SponsorsStep } from "./SponsorsStep";
import { canWithdraw, verifyView, type StepItem } from "./verify-model";
import { VerifyCard, VerifyError, VerifyIcon, primaryButton, primaryStyle, secondaryStyle, dangerStyle } from "./verify-ui";

/**
 * Συναθλητές › Επαλήθευση (ADR-280 §2, §6): for people without an active
 * membership. Consent, two sponsors from one's verified Φιλαράκια (or a
 * single-use QR/link), a mobile number with an SMS code and a selfie holding
 * a 4-digit code, then «Στον έλεγχο από την ομάδα του Palee». People verified
 * through a membership only see that they are verified.
 */
export function PartnerVerifyPage() {
  const t = useTranslations("PartnerVerify");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const overview = useQuery({
    queryKey: VERIFICATION_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchVerification(token!),
  });

  return (
    <div className="flex min-w-0 flex-col gap-4" data-testid="partner-verify">
      <header className="flex flex-col gap-1">
        <BackLink href="/partners" className="self-start text-sm font-semibold">{t("back")}</BackLink>
        <h1 className="text-2xl font-bold" style={{ color: "var(--text)" }}>{t("title")}</h1>
      </header>
      {overview.isPending ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("loading")}</p> : null}
      {overview.error ? <VerifyError error={overview.error} /> : null}
      {token && overview.data ? <VerifyBody token={token} overview={overview.data} /> : null}
    </div>
  );
}

function VerifyBody({ token, overview }: { token: string; overview: VerificationOverview }) {
  const t = useTranslations("PartnerVerify");
  const view = verifyView(overview);

  if (view.kind === "verified") {
    return (
      <VerifyCard testId="verify-verified">
        <p className="flex items-center gap-2 text-lg font-semibold" style={{ color: "var(--success)" }}>
          <VerifyIcon name="shield" /> {t("verified.title")}
        </p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {view.method === "sponsors" ? t("verified.bySponsors") : t("verified.byMembership")}
        </p>
        <Link href="/partners" className={`${primaryButton} self-start`} style={primaryStyle}>{t("verified.open")}</Link>
      </VerifyCard>
    );
  }

  if (view.kind === "suspended") {
    return (
      <VerifyCard testId="verify-suspended">
        <p className="flex items-center gap-2 text-lg font-semibold" style={{ color: "var(--danger)" }}>
          <VerifyIcon name="alert" /> {t("suspended.title")}
        </p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("suspended.body")}</p>
      </VerifyCard>
    );
  }

  if (view.kind === "in_review") {
    return (
      <>
        <VerifyCard testId="verify-in-review">
          <p className="flex items-center gap-2 text-lg font-semibold" style={{ color: "var(--text)" }}>
            <VerifyIcon name="clock" /> {t("review.title")}
          </p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {t("review.body", { days: overview.limits.selfie_retention_days })}
          </p>
        </VerifyCard>
        <WithdrawBlock token={token} request={view.request} />
      </>
    );
  }

  if (view.kind === "rejected") return <RejectedCard token={token} reason={view.reason} />;

  return (
    <>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("intro", { count: overview.limits.sponsors_required })}</p>
      {view.selfieExpired ? (
        <p role="status" className="flex items-start gap-2 rounded-2xl p-3 text-sm" style={{ background: "var(--panel-muted)", color: "var(--warning)" }}>
          <VerifyIcon name="alert" /> {t("selfieExpired", { days: overview.limits.selfie_retention_days })}
        </p>
      ) : null}
      <ol className="flex min-w-0 flex-col gap-3" aria-label={t("stepsLabel")}>
        {view.steps.map((step, index) => (
          <li key={step.key} className="min-w-0" data-testid={`verify-step-${step.key}`} data-state={step.state}>
            <StepFrame step={step} index={index}>
              {step.state === "open" ? (
                <StepBody step={step} token={token} overview={overview} />
              ) : step.state === "locked" ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>{t(`steps.${step.key}.locked`)}</p>
              ) : (
                <DoneLine step={step} request={view.request} />
              )}
            </StepFrame>
          </li>
        ))}
      </ol>
      {canWithdraw(view.request) ? <WithdrawBlock token={token} request={view.request} /> : null}
    </>
  );
}

function StepFrame({ step, index, children }: { step: StepItem; index: number; children: ReactNode }) {
  const t = useTranslations("PartnerVerify");
  const done = step.state === "done";
  const locked = step.state === "locked";
  return (
    <VerifyCard>
      <div className="flex min-w-0 items-center gap-3">
        <span
          className="flex size-8 shrink-0 items-center justify-center rounded-full text-sm font-bold"
          style={{
            background: done ? "var(--success)" : locked ? "var(--panel-raised)" : "var(--primary)",
            color: done ? "var(--primary-contrast)" : locked ? "var(--dim)" : "var(--primary-contrast)",
          }}
          aria-hidden="true"
        >
          {done ? <VerifyIcon name="check" size={18} /> : locked ? <VerifyIcon name="lock" size={16} /> : index + 1}
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t(`steps.${step.key}.title`)}</h2>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {t("stepOf", { step: index + 1, total: 4 })} · {t(`state.${step.state}`)}
          </p>
        </div>
      </div>
      {children}
    </VerifyCard>
  );
}

function DoneLine({ step, request }: { step: StepItem; request: VerificationRequest | null }) {
  const t = useTranslations("PartnerVerify");
  if (step.key === "sponsors" && request) {
    const names = request.sponsors
      .filter((sponsor) => sponsor.status === "vouched")
      .map((sponsor) => sponsor.person.nickname ?? t("someone"))
      .join(", ");
    return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("steps.sponsors.done", { names })}</p>;
  }
  if (step.key === "phone" && request?.phone) {
    return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("steps.phone.done", { phone: request.phone })}</p>;
  }
  return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`steps.${step.key}.doneShort`)}</p>;
}

function StepBody({ step, token, overview }: { step: StepItem; token: string; overview: VerificationOverview }) {
  const request = overview.request;
  switch (step.key) {
    case "consent":
      return <ConsentStep token={token} overview={overview} />;
    case "sponsors":
      return request ? <SponsorsStep token={token} request={request} limits={overview.limits} /> : null;
    case "phone":
      return request ? <PhoneStep token={token} request={request} limits={overview.limits} /> : null;
    case "selfie":
      return request ? <SelfieStep token={token} request={request} limits={overview.limits} /> : null;
  }
}

function useSetOverview() {
  const queryClient = useQueryClient();
  return (next: VerificationOverview) => {
    queryClient.setQueryData(VERIFICATION_KEY, next);
    void queryClient.invalidateQueries({ queryKey: ["my", "partners"] });
  };
}

const CONSENT_POINTS = ["what", "phone", "selfie", "human", "keep", "withdraw"] as const;

function ConsentStep({ token, overview }: { token: string; overview: VerificationOverview }) {
  const t = useTranslations("PartnerVerify");
  const setOverview = useSetOverview();
  const consent = useMutation({ mutationFn: () => giveConsent(token), onSuccess: setOverview });
  const values = {
    count: overview.limits.sponsors_required,
    days: overview.limits.selfie_retention_days,
  };
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(event) => {
        event.preventDefault();
        consent.mutate();
      }}
    >
      <ul className="flex list-disc flex-col gap-1.5 ps-5 text-sm" style={{ color: "var(--text-soft)" }}>
        {CONSENT_POINTS.map((point) => (
          <li key={point}>{t(`consent.${point}`, values)}</li>
        ))}
      </ul>
      <Link href="/privacy#partners" className="self-start text-sm font-semibold underline" style={{ color: "var(--primary)" }}>
        {t("consent.privacy")}
      </Link>
      <VerifyError error={consent.error} />
      <button type="submit" className={`${primaryButton} self-start`} style={primaryStyle} disabled={consent.isPending}>
        {t("consent.agree")}
      </button>
    </form>
  );
}

function RejectedCard({ token, reason }: { token: string; reason: string | null }) {
  const t = useTranslations("PartnerVerify");
  const setOverview = useSetOverview();
  const again = useMutation({ mutationFn: () => giveConsent(token), onSuccess: setOverview });
  return (
    <VerifyCard testId="verify-rejected">
      <p className="flex items-center gap-2 text-lg font-semibold" style={{ color: "var(--text)" }}>
        <VerifyIcon name="alert" /> {t("rejected.title")}
      </p>
      {reason ? (
        <p className="text-sm" style={{ color: "var(--text)" }}>
          <span className="font-semibold">{t("rejected.reason")}</span> {reason}
        </p>
      ) : null}
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("rejected.again")}</p>
      <VerifyError error={again.error} />
      <button type="button" className={`${primaryButton} self-start`} style={primaryStyle} disabled={again.isPending} onClick={() => again.mutate()}>
        {t("rejected.ask")}
      </button>
    </VerifyCard>
  );
}

/** «Ακύρωση και διαγραφή στοιχείων», confirmed inside the page. */
function WithdrawBlock({ token, request }: { token: string; request: VerificationRequest | null }) {
  const t = useTranslations("PartnerVerify");
  const setOverview = useSetOverview();
  const [confirming, setConfirming] = useState(false);
  const withdraw = useMutation({
    mutationFn: () => withdrawVerification(token),
    onSuccess: (next) => {
      setConfirming(false);
      setOverview(next);
    },
  });
  if (!canWithdraw(request)) return null;
  return (
    <section className="flex flex-col gap-2" data-testid="verify-withdraw">
      {confirming ? (
        <div className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} role="group" aria-label={t("withdraw.button")}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("withdraw.confirmTitle")}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("withdraw.confirmBody")}</p>
          <VerifyError error={withdraw.error} />
          <div className="flex flex-wrap gap-2">
            <button type="button" className={primaryButton} style={dangerStyle} disabled={withdraw.isPending} onClick={() => withdraw.mutate()}>
              {t("withdraw.confirm")}
            </button>
            <button type="button" className={primaryButton} style={secondaryStyle} disabled={withdraw.isPending} onClick={() => setConfirming(false)}>
              {t("withdraw.keep")}
            </button>
          </div>
        </div>
      ) : (
        <button type="button" className="self-start text-sm font-semibold underline" style={{ color: "var(--danger)" }} onClick={() => setConfirming(true)}>
          {t("withdraw.button")}
        </button>
      )}
    </section>
  );
}
