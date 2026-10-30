"use client";

import { useEffect, useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  DECISION_TEXT_MAX,
  PLATFORM_VERIFICATIONS_KEY,
  decidePlatformVerification,
  fetchPlatformVerification,
  fetchPlatformVerifications,
  type PlatformVerification,
  type PlatformVerificationItem,
} from "@/api/platform-partners";
import { errorFor } from "@/components/partner-verify/verify-model";
import { VerifyError } from "@/components/partner-verify/verify-ui";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { withClock } from "@/lib/clock";

const buttonClass = "min-h-10 px-4 text-sm font-semibold disabled:opacity-50";
const SELFIE_REFRESH_MS = 1000;

/**
 * Platform console › Επαληθεύσεις Συναθλητών (ADR-280 §2, option A): the
 * requests waiting for the Palee check. A person compares the selfie (a
 * 5-minute link) holding the request's code with the avatar, sees the
 * sponsors and the masked number, and approves or rejects with a reason.
 * The photo is deleted when the decision is taken.
 */
export function PlatformPartnerVerificationsPage() {
  const t = useTranslations("PlatformPartners");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queue = useQuery({
    queryKey: PLATFORM_VERIFICATIONS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchPlatformVerifications(token!),
  });
  const [selected, setSelected] = useState<string | null>(null);
  const [decided, setDecided] = useState<string | null>(null);
  const forbidden = queue.error instanceof ApiError && queue.error.status === 403;
  const requests = queue.data?.requests ?? [];

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6" data-testid="platform-partner-verifications">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("verifications.title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("verifications.subtitle")}</p>
      </header>
      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {queue.error && !forbidden ? <div className="mt-6"><VerifyError error={queue.error} /></div> : null}
      {decided ? (
        <p role="status" className="mt-4 text-sm font-semibold text-[var(--success)]">{decided}</p>
      ) : null}
      {token && queue.data ? (
        <div className="mt-6 grid min-w-0 gap-6 lg:grid-cols-[18rem_minmax(0,1fr)]">
          <section className="flex min-w-0 flex-col gap-2" aria-label={t("verifications.queue")}>
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">
              {t("verifications.queueCount", { count: requests.length })}
            </h2>
            {requests.length === 0 ? <p className="text-sm text-[var(--text-soft)]">{t("verifications.empty")}</p> : null}
            {requests.map((item) => (
              <QueueRow key={item.id} item={item} active={item.id === selected} onOpen={() => { setSelected(item.id); setDecided(null); }} />
            ))}
          </section>
          {selected ? (
            <VerificationDetail
              key={selected}
              token={token}
              id={selected}
              onDecided={(message) => {
                setSelected(null);
                setDecided(message);
              }}
            />
          ) : requests.length > 0 ? (
            <p className="text-sm text-[var(--text-soft)]">{t("verifications.pick")}</p>
          ) : null}
        </div>
      ) : null}
    </main>
  );
}

function QueueRow({ item, active, onOpen }: { item: PlatformVerificationItem; active: boolean; onOpen: () => void }) {
  const t = useTranslations("PlatformPartners");
  const format = useFormatter();
  const locale = useLocale();
  return (
    <button
      type="button"
      onClick={onOpen}
      aria-pressed={active}
      data-testid={`verification-row-${item.id}`}
      className="flex min-w-0 items-center gap-3 border p-3 text-start"
      style={{ borderColor: active ? "var(--primary)" : "var(--border)", background: "var(--panel)" }}
    >
      <PersonAvatar name={item.person.nickname} url={item.person.avatar_url} size={36} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold text-[var(--text)]">{item.person.nickname ?? t("someone")}</span>
        <span className="block text-xs text-[var(--text-soft)]">
          {item.submitted_at ? t("verifications.submitted", { date: format.dateTime(new Date(item.submitted_at), withClock(locale, { dateStyle: "medium", timeStyle: "short" })) }) : "—"}
        </span>
        {item.overdue ? <span className="block text-xs font-semibold text-[var(--warning)]">{t("verifications.overdue")}</span> : null}
      </span>
    </button>
  );
}

function VerificationDetail({ token, id, onDecided }: { token: string; id: string; onDecided: (message: string) => void }) {
  const t = useTranslations("PlatformPartners");
  const format = useFormatter();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const reasonId = useId();
  const detail = useQuery({
    queryKey: [...PLATFORM_VERIFICATIONS_KEY, id],
    queryFn: () => fetchPlatformVerification(token, id),
    staleTime: 0,
    gcTime: 0,
  });
  const [now, setNow] = useState(() => Date.now());
  // When the selfie link was fetched: it lives `selfie_url_expires_in` seconds from then.
  const loadedAt = detail.dataUpdatedAt || now;
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), SELFIE_REFRESH_MS);
    return () => window.clearInterval(timer);
  }, []);
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState("");
  const [reasonMissing, setReasonMissing] = useState(false);
  const decide = useMutation({
    mutationFn: (decision: "approve" | "reject") =>
      decidePlatformVerification(token, id, decision === "reject" ? { decision, reason: reason.trim() } : { decision }),
    onSuccess: (_result, decision) => {
      void queryClient.invalidateQueries({ queryKey: PLATFORM_VERIFICATIONS_KEY });
      const name = detail.data?.person.nickname ?? t("someone");
      onDecided(decision === "approve" ? t("verifications.approved", { name }) : t("verifications.rejected", { name }));
    },
  });

  if (detail.isPending) return <p className="text-sm text-[var(--text-soft)]">{t("loading")}</p>;
  if (detail.error) return <VerifyError error={detail.error} />;
  const request: PlatformVerification = detail.data;
  const linkLeft = Math.max(0, request.selfie_url_expires_in - Math.floor((now - loadedAt) / 1000));
  const linkExpired = linkLeft === 0;
  const reasonError = errorFor(decide.error, "reason");
  const name = request.person.nickname ?? t("someone");

  return (
    <article className="flex min-w-0 flex-col gap-4 border border-[var(--border)] bg-[var(--panel)] p-4" data-testid="verification-detail" aria-label={name}>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-xl font-semibold text-[var(--text)]">{name}</h2>
        <span className="text-xs text-[var(--text-soft)]">
          {request.submitted_at ? t("verifications.submitted", { date: format.dateTime(new Date(request.submitted_at), withClock(locale, { dateStyle: "medium", timeStyle: "short" })) }) : null}
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <p className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("verifications.codeToFind")}</p>
        <p className="font-mono text-3xl font-bold tracking-[0.3em] text-[var(--text)]" dir="ltr" data-testid="verification-code">{request.selfie_code}</p>
      </div>

      <div className="grid min-w-0 gap-4 sm:grid-cols-2">
        <figure className="flex min-w-0 flex-col gap-2">
          <figcaption className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("verifications.selfie")}</figcaption>
          {request.selfie_url && !linkExpired ? (
            // eslint-disable-next-line @next/next/no-img-element -- a private, short-lived presigned link
            <img src={request.selfie_url} alt={t("verifications.selfieAlt", { name })} className="max-h-96 w-full bg-[var(--panel-muted)] object-contain" data-testid="verification-selfie" />
          ) : (
            <p className="flex min-h-40 items-center justify-center bg-[var(--panel-muted)] p-3 text-center text-sm text-[var(--text-soft)]">
              {request.selfie_url ? t("verifications.linkExpired") : t("verifications.noSelfie")}
            </p>
          )}
          <div className="flex flex-wrap items-center gap-2 text-xs text-[var(--text-soft)]">
            {request.selfie_url && !linkExpired ? <span>{t("verifications.linkLeft", { seconds: linkLeft })}</span> : null}
            <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text-soft)]`} onClick={() => void detail.refetch()} disabled={detail.isFetching}>
              {t("verifications.refreshLink")}
            </button>
          </div>
        </figure>
        <figure className="flex min-w-0 flex-col gap-2">
          <figcaption className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("verifications.avatar")}</figcaption>
          {request.person.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
            <img src={request.person.avatar_url} alt={t("verifications.avatarAlt", { name })} className="max-h-96 w-full bg-[var(--panel-muted)] object-contain" />
          ) : (
            <p className="flex min-h-40 items-center justify-center bg-[var(--panel-muted)] p-3 text-center text-sm text-[var(--text-soft)]">{t("verifications.noAvatar")}</p>
          )}
        </figure>
      </div>

      <dl className="grid min-w-0 gap-3 text-sm sm:grid-cols-2">
        <div className="min-w-0">
          <dt className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("verifications.sponsors")}</dt>
          <dd className="mt-1 flex flex-col gap-1">
            {request.sponsors.length === 0 ? <span className="text-[var(--text-soft)]">—</span> : null}
            {request.sponsors.map((sponsor) => (
              <span key={sponsor.person.id} className="flex min-w-0 items-center gap-2 text-[var(--text)]">
                <PersonAvatar name={sponsor.person.nickname} url={sponsor.person.avatar_url} size={24} />
                <span className="truncate">{sponsor.person.nickname ?? t("someone")}</span>
                <span className="shrink-0 text-xs text-[var(--text-soft)]">· {t(`verifications.channel.${sponsor.channel}`)}</span>
              </span>
            ))}
          </dd>
        </div>
        <div className="min-w-0">
          <dt className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("verifications.phone")}</dt>
          <dd className="mt-1 text-[var(--text)]" dir="ltr">
            {request.phone ?? "—"} {request.phone_verified ? <span className="text-xs text-[var(--success)]">· {t("verifications.phoneVerified")}</span> : null}
          </dd>
        </div>
      </dl>

      <p className="text-xs text-[var(--text-soft)]">{t("verifications.deletedNote")}</p>

      {rejecting ? (
        <form
          className="flex flex-col gap-2"
          noValidate
          onSubmit={(event) => {
            event.preventDefault();
            if (!reason.trim()) {
              setReasonMissing(true);
              return;
            }
            decide.mutate("reject");
          }}
        >
          <label htmlFor={reasonId} className="text-xs font-semibold text-[var(--text-soft)]">{t("verifications.reason")}</label>
          <textarea
            id={reasonId}
            className="min-h-20 w-full border border-[var(--border)] bg-[var(--panel)] p-3 text-sm text-[var(--text)]"
            value={reason}
            maxLength={DECISION_TEXT_MAX}
            aria-invalid={reasonMissing || Boolean(reasonError)}
            onChange={(event) => {
              setReason(event.target.value);
              setReasonMissing(false);
            }}
          />
          <p className="text-xs text-[var(--dim)]">{t("verifications.reasonHint")}</p>
          {reasonMissing ? <ErrorNotice variant="field">{t("verifications.reasonRequired")}</ErrorNotice> : null}
          {reasonError ? <VerifyError error={reasonError} field /> : null}
          {!reasonError && decide.error ? <VerifyError error={decide.error} /> : null}
          <div className="flex flex-wrap gap-2">
            <button type="submit" className={`${buttonClass} bg-[var(--danger)] text-[var(--danger-contrast)]`} disabled={decide.isPending}>
              {t("verifications.confirmReject")}
            </button>
            <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text-soft)]`} onClick={() => setRejecting(false)} disabled={decide.isPending}>
              {t("cancel")}
            </button>
          </div>
        </form>
      ) : (
        <div className="flex flex-col gap-2">
          {decide.error ? <VerifyError error={decide.error} /> : null}
          <div className="flex flex-wrap gap-2">
            <button type="button" className={`${buttonClass} bg-[var(--accent)] text-[var(--primary-contrast)]`} disabled={decide.isPending} onClick={() => decide.mutate("approve")}>
              {t("verifications.approve")}
            </button>
            <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text)]`} disabled={decide.isPending} onClick={() => setRejecting(true)}>
              {t("verifications.reject")}
            </button>
          </div>
        </div>
      )}
    </article>
  );
}
