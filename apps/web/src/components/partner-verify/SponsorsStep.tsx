"use client";

import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  SPONSOR_CANDIDATES_KEY,
  VERIFICATION_KEY,
  askSponsor,
  cancelSponsor,
  createSponsorLink,
  fetchSponsorCandidates,
  type SponsorCandidate,
  type SponsorLink,
  type VerificationLimits,
  type VerificationRequest,
} from "@/api/partner-verification";
import { QrCode } from "@/components/referrals/QrCode";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { Dialog } from "@/components/ui/Dialog";

import { candidateAction, formatCountdown, secondsLeft, sortCandidates } from "./verify-model";
import { VerifyError, VerifyIcon, primaryButton, primaryStyle, secondaryStyle } from "./verify-ui";

/**
 * Step 2: two sponsors. The main way is one's verified Φιλαράκια with «Ζήτα»;
 * at the end a collapsed «Αυτός που σε ξέρει δεν είναι εδώ;» opens a QR and
 * a single-use, 10-minute link for someone met in person.
 */
export function SponsorsStep({ token, request, limits }: { token: string; request: VerificationRequest; limits: VerificationLimits }) {
  const t = useTranslations("PartnerVerify");
  const queryClient = useQueryClient();
  const candidates = useQuery({
    queryKey: SPONSOR_CANDIDATES_KEY,
    queryFn: () => fetchSponsorCandidates(token),
    // Answers come from other people: look again now and then.
    refetchInterval: 30_000,
  });
  const [failed, setFailed] = useState<{ id: string; error: unknown } | null>(null);
  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: SPONSOR_CANDIDATES_KEY });
    void queryClient.invalidateQueries({ queryKey: VERIFICATION_KEY });
  };
  const act = useMutation({
    mutationFn: ({ id, action }: { id: string; action: "ask" | "cancel" }) =>
      action === "ask" ? askSponsor(token, id) : cancelSponsor(token, id),
    onMutate: () => setFailed(null),
    onError: (error, { id }) => setFailed({ id, error }),
    onSuccess: refresh,
  });
  const [othersOpen, setOthersOpen] = useState(false);
  const [linkOpen, setLinkOpen] = useState(false);
  const required = candidates.data?.required ?? request.sponsors_required;
  const vouches = candidates.data?.vouches ?? request.vouches;
  const enough = vouches >= required;
  const buddyIds = new Set(candidates.data?.candidates.map((candidate) => candidate.person.id));
  const viaLink = request.sponsors.filter((sponsor) => sponsor.channel === "link" && !buddyIds.has(sponsor.person.id));

  return (
    <div className="flex min-w-0 flex-col gap-3" data-testid="sponsors-step">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("sponsors.lead", { count: required })}</p>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }} data-testid="sponsors-count">
        {t("sponsors.count", { vouches, required })}
      </p>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("sponsors.meaning")}</p>
      {candidates.error ? <VerifyError error={candidates.error} /> : null}
      {candidates.data && candidates.data.candidates.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("sponsors.noBuddies")}</p>
      ) : null}
      <ul className="flex min-w-0 flex-col gap-1" aria-label={t("sponsors.listLabel")}>
        {sortCandidates(candidates.data?.candidates ?? []).map((candidate) => (
          <CandidateRow
            key={candidate.person.id}
            candidate={candidate}
            enough={enough}
            busy={act.isPending && act.variables?.id === candidate.person.id}
            error={failed?.id === candidate.person.id ? failed.error : null}
            onAct={(action) => act.mutate({ id: candidate.person.id, action })}
          />
        ))}
        {viaLink.map((sponsor) => (
          <li key={sponsor.id} className="flex min-h-12 min-w-0 items-center gap-3 py-1">
            <PersonAvatar name={sponsor.person.nickname} url={sponsor.person.avatar_url} size={40} />
            <span className="min-w-0 flex-1">
              <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{sponsor.person.nickname ?? t("someone")}</span>
              <span className="block text-xs" style={{ color: "var(--success)" }}>{t("sponsors.viaLink")}</span>
            </span>
          </li>
        ))}
      </ul>
      {!enough ? (
        <div className="flex flex-col gap-2 border-t pt-3" style={{ borderColor: "var(--border)" }}>
          <button
            type="button"
            aria-expanded={othersOpen}
            aria-controls="sponsor-others"
            className="flex min-h-11 items-center justify-between gap-2 text-start text-sm font-semibold"
            style={{ color: "var(--text)" }}
            onClick={() => setOthersOpen((open) => !open)}
          >
            {t("sponsors.othersTitle")}
            <span aria-hidden="true" style={{ transform: othersOpen ? "rotate(180deg)" : undefined }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="m6 9 6 6 6-6" /></svg>
            </span>
          </button>
          {othersOpen ? (
            <div id="sponsor-others" className="flex flex-col gap-2">
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("sponsors.othersBody")}</p>
              <button type="button" className={`${primaryButton} self-start`} style={secondaryStyle} onClick={() => setLinkOpen(true)}>
                <VerifyIcon name="qr" /> {t("sponsors.showQr")}
              </button>
            </div>
          ) : null}
        </div>
      ) : null}
      {linkOpen ? <SponsorLinkDialog token={token} minutes={limits.link_minutes} startVouches={vouches} onClose={() => setLinkOpen(false)} /> : null}
    </div>
  );
}

function CandidateRow({
  candidate,
  enough,
  busy,
  error,
  onAct,
}: {
  candidate: SponsorCandidate;
  enough: boolean;
  busy: boolean;
  error: unknown;
  onAct: (action: "ask" | "cancel") => void;
}) {
  const t = useTranslations("PartnerVerify");
  const action = candidateAction(candidate, enough);
  const status = candidate.sponsorship?.status;
  const name = candidate.person.nickname ?? t("someone");
  let line: string;
  let color = "var(--dim)";
  if (status === "vouched") {
    line = t("sponsors.state.vouched");
    color = "var(--success)";
  } else if (status === "requested") {
    line = t("sponsors.state.requested");
    color = "var(--text-soft)";
  } else if (status === "declined") {
    line = t("sponsors.state.declined");
  } else if (candidate.eligible) {
    line = t("sponsors.state.eligible");
    color = "var(--success)";
  } else {
    line = t(`sponsors.reason.${candidate.reason ?? "not_verified"}`);
  }
  return (
    <li className="flex min-w-0 flex-col gap-1 py-1" data-testid={`sponsor-${candidate.person.id}`}>
      <div className="flex min-h-12 min-w-0 items-center gap-3">
        <PersonAvatar name={candidate.person.nickname} url={candidate.person.avatar_url} size={40} />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
          <span className="flex items-center gap-1 text-xs" style={{ color }}>
            {status === "vouched" ? <VerifyIcon name="check" size={14} /> : status === "requested" ? <VerifyIcon name="clock" size={14} /> : null}
            {line}
          </span>
        </span>
        {action === "ask" ? (
          <button type="button" className={`${primaryButton} shrink-0`} style={primaryStyle} disabled={busy} onClick={() => onAct("ask")} aria-label={t("sponsors.askLabel", { name })}>
            {t("sponsors.ask")}
          </button>
        ) : action === "cancel" ? (
          <button type="button" className={`${primaryButton} shrink-0`} style={secondaryStyle} disabled={busy} onClick={() => onAct("cancel")} aria-label={t("sponsors.cancelLabel", { name })}>
            {t("sponsors.cancel")}
          </button>
        ) : null}
      </div>
      {error ? <VerifyError error={error} field /> : null}
    </li>
  );
}

/**
 * «Εγγύηση από κοντά»: a QR and the link, single use, with a countdown. While
 * it is open the page looks for a new vouch every few seconds.
 */
function SponsorLinkDialog({ token, minutes, startVouches, onClose }: { token: string; minutes: number; startVouches: number; onClose: () => void }) {
  const t = useTranslations("PartnerVerify");
  const queryClient = useQueryClient();
  const [link, setLink] = useState<SponsorLink | null>(null);
  const [copied, setCopied] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  const create = useMutation({
    mutationFn: () => createSponsorLink(token),
    onSuccess: (next) => {
      setLink(next);
      setCopied(false);
      setNow(Date.now());
    },
  });
  const { mutate: createLink } = create;
  // One link per opening, even when React runs the effect twice in dev.
  const requested = useRef(false);
  useEffect(() => {
    if (requested.current) return;
    requested.current = true;
    createLink();
  }, [createLink]);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);
  const candidates = useQuery({
    queryKey: SPONSOR_CANDIDATES_KEY,
    queryFn: () => fetchSponsorCandidates(token),
    refetchInterval: 5_000,
  });
  const vouched = (candidates.data?.vouches ?? startVouches) > startVouches;
  useEffect(() => {
    if (vouched) void queryClient.invalidateQueries({ queryKey: VERIFICATION_KEY });
  }, [vouched, queryClient]);
  const left = link ? secondsLeft(link.expires_at, now) : minutes * 60;
  const expired = Boolean(link) && left === 0;

  return (
    <Dialog onClose={onClose} title={t("link.title")} variant="screen" size="md" testId="sponsor-link-dialog">
      <div className="flex flex-col items-center gap-4 text-center">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("link.body")}</p>
        {vouched ? (
          <p role="status" className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--success)" }}>
            <VerifyIcon name="check" /> {t("link.vouched")}
          </p>
        ) : null}
        {link && !expired ? (
          <>
            <div className="rounded-2xl p-3" style={{ background: "var(--panel-raised)" }} data-testid="sponsor-link-qr">
              <QrCode value={link.url} size={208} label={t("link.qrLabel")} />
            </div>
            <p className="text-sm" style={{ color: "var(--text)" }} data-testid="sponsor-link-countdown" aria-live="off">
              {t("link.expiresIn", { time: formatCountdown(left) })}
            </p>
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("link.singleUse")}</p>
            <button
              type="button"
              className={primaryButton}
              style={primaryStyle}
              onClick={() => {
                void navigator.clipboard?.writeText(link.url).then(() => setCopied(true));
              }}
            >
              <VerifyIcon name="copy" /> {copied ? t("link.copied") : t("link.copy")}
            </button>
          </>
        ) : null}
        {expired ? (
          <>
            <p className="text-sm font-semibold" style={{ color: "var(--warning)" }}>{t("link.expired")}</p>
            <button type="button" className={primaryButton} style={primaryStyle} disabled={create.isPending} onClick={() => create.mutate()}>
              {t("link.renew")}
            </button>
          </>
        ) : null}
        {create.isPending && !link ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("loading")}</p> : null}
        <VerifyError error={create.error} />
      </div>
    </Dialog>
  );
}
