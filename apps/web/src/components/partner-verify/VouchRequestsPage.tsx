"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  VOUCH_REQUESTS_KEY,
  decideVouch,
  fetchVouchRequests,
  type VouchDecision,
  type VouchRequest,
  type Vouching,
} from "@/api/partner-verification";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { BackLink } from "@/components/ui/BackLink";

import { VerifyCard, VerifyError, VerifyIcon, primaryButton, primaryStyle, secondaryStyle } from "./verify-ui";

/**
 * The sponsor's side (ADR-280 §2): people who asked you to vouch for them,
 * each a card «… σε ζητά εγγυητή» stating what vouching means before
 * «Εγγυώμαι» / «Δεν τον ξέρω», with your quota and any 60-day pause.
 */
export function VouchRequestsPage() {
  const t = useTranslations("PartnerVerify");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const requests = useQuery({ queryKey: VOUCH_REQUESTS_KEY, enabled: Boolean(token), queryFn: () => fetchVouchRequests(token!) });
  const [answered, setAnswered] = useState<{ name: string; decision: VouchDecision } | null>(null);
  const [failed, setFailed] = useState<{ id: string; error: unknown } | null>(null);
  const decide = useMutation({
    mutationFn: ({ request, decision }: { request: VouchRequest; decision: VouchDecision }) => decideVouch(token!, request.id, decision),
    onMutate: () => setFailed(null),
    onError: (error, { request }) => setFailed({ id: request.id, error }),
    onSuccess: (_result, { request, decision }) => {
      setAnswered({ name: request.person.nickname ?? t("someone"), decision });
      void queryClient.invalidateQueries({ queryKey: VOUCH_REQUESTS_KEY });
    },
  });
  const vouching = requests.data?.vouching;

  return (
    <div className="flex min-w-0 flex-col gap-4" data-testid="vouch-requests">
      <header className="flex flex-col gap-1">
        <BackLink href="/partners" className="self-start text-sm font-semibold">{t("back")}</BackLink>
        <h1 className="text-2xl font-bold" style={{ color: "var(--text)" }}>{t("vouch.title")}</h1>
      </header>
      {requests.isPending ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("loading")}</p> : null}
      {requests.error ? <VerifyError error={requests.error} /> : null}
      {answered ? (
        <p role="status" className="flex items-center gap-2 text-sm font-semibold" style={{ color: answered.decision === "vouch" ? "var(--success)" : "var(--text-soft)" }}>
          <VerifyIcon name={answered.decision === "vouch" ? "check" : "close"} />
          {answered.decision === "vouch" ? t("vouch.didVouch", { name: answered.name }) : t("vouch.didDecline", { name: answered.name })}
        </p>
      ) : null}
      {vouching ? <VouchingStanding vouching={vouching} /> : null}
      {requests.data && requests.data.requests.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("vouch.none")}</p>
      ) : null}
      {requests.data?.requests.map((request) => (
        <VouchRequestCard
          key={request.id}
          request={request}
          canVouch={vouching?.can_vouch ?? false}
          busy={decide.isPending && decide.variables?.request.id === request.id}
          error={failed?.id === request.id ? failed.error : null}
          onDecide={(decision) => decide.mutate({ request, decision })}
        />
      ))}
    </div>
  );
}

/** Your quota left and any pause, in one line. */
export function VouchingStanding({ vouching }: { vouching: Vouching }) {
  const t = useTranslations("PartnerVerify");
  const format = useFormatter();
  let text: string;
  if (vouching.reason === "penalty" && vouching.penalty_until) {
    text = t("vouch.paused", { date: format.dateTime(new Date(vouching.penalty_until), { dateStyle: "long" }) });
  } else if (vouching.reason === "not_verified") {
    text = t("vouch.notVerified");
  } else if (vouching.reason === "quota") {
    text = t("vouch.quotaUsed", { quota: vouching.quota, days: vouching.window_days });
  } else {
    text = t("vouch.quotaLeft", { left: vouching.left, quota: vouching.quota, days: vouching.window_days });
  }
  return (
    <p className="text-sm" data-testid="vouching-standing" style={{ color: vouching.can_vouch ? "var(--text-soft)" : "var(--warning)" }}>
      {text}
    </p>
  );
}

function VouchRequestCard({
  request,
  canVouch,
  busy,
  error,
  onDecide,
}: {
  request: VouchRequest;
  canVouch: boolean;
  busy: boolean;
  error: unknown;
  onDecide: (decision: VouchDecision) => void;
}) {
  const t = useTranslations("PartnerVerify");
  const name = request.person.nickname ?? t("someone");
  return (
    <VerifyCard testId={`vouch-request-${request.id}`}>
      <div className="flex min-w-0 items-center gap-3">
        <PersonAvatar name={request.person.nickname} url={request.person.avatar_url} size={48} />
        <div className="min-w-0">
          <p className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("vouch.asks", { name })}</p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("vouch.forPartners")}</p>
        </div>
      </div>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("vouch.meaning")}</p>
      <VerifyError error={error} />
      <div className="flex flex-wrap gap-2">
        <button type="button" className={primaryButton} style={primaryStyle} disabled={busy || !canVouch} onClick={() => onDecide("vouch")}>
          <VerifyIcon name="shield" /> {t("vouch.vouch")}
        </button>
        <button type="button" className={primaryButton} style={secondaryStyle} disabled={busy} onClick={() => onDecide("decline")}>
          {t("vouch.decline")}
        </button>
      </div>
    </VerifyCard>
  );
}
