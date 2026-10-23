"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  PASSWORD_RESETS_KEY,
  claimPasswordReset,
  dismissPasswordReset,
  issuePasswordResetLink,
  rejectPasswordReset,
  releasePasswordReset,
  type PasswordResetInbox,
  type PasswordResetLink,
  type PasswordResetRequest,
} from "@/api/password-resets";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { SendPanel } from "@/components/password-resets/SendPanel";
import { StateChip } from "@/components/password-resets/StateChip";
import { relativeTime } from "@/components/password-resets/reset-email";
import { canTakeOver, claimerName, sourceLabels } from "@/components/password-resets/request-labels";
import { useNow } from "@/components/password-resets/use-now";

const primaryButton =
  "rounded-full bg-[var(--accent)] px-5 py-3 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-40";
const secondaryButton =
  "rounded-full border border-[var(--border)] px-4 py-2.5 text-sm font-semibold text-[var(--text-soft)] disabled:opacity-40";

/**
 * One request, opened. Opening claims it, so two handlers never mail the
 * same person; the holder checks it is really them off-app and creates the
 * one-time link, which they then mail from their own mailbox.
 */
export function RequestView({ id, request, loading }: { id: string; request: PasswordResetRequest | null; loading: boolean }) {
  const t = useTranslations("passwordResets");
  const locale = useLocale();
  const now = useNow();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? "";
  const [issued, setIssued] = useState<PasswordResetLink | null>(null);
  const [confirmingReject, setConfirmingReject] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const claimTried = useRef(false);

  const replace = (next: PasswordResetRequest) =>
    queryClient.setQueryData<PasswordResetInbox>(PASSWORD_RESETS_KEY, (current) =>
      current ? { ...current, requests: current.requests.map((entry) => (entry.id === next.id ? next : entry)) } : current,
    );
  const remove = () =>
    queryClient.setQueryData<PasswordResetInbox>(PASSWORD_RESETS_KEY, (current) =>
      current ? { ...current, requests: current.requests.filter((entry) => entry.id !== id) } : current,
    );
  const backToList = () => router.push("/password-resets");
  const onError = (error: unknown) => {
    if (error instanceof ApiError && error.status === 409) {
      setNotice(null);
      void queryClient.invalidateQueries({ queryKey: PASSWORD_RESETS_KEY });
      return;
    }
    if (error instanceof ApiError && error.status === 404) {
      remove();
      return;
    }
    setNotice(t("actionError"));
  };

  const claim = useMutation({
    mutationFn: () => claimPasswordReset(token, id),
    onSuccess: ({ request: next }) => {
      setNotice(null);
      replace(next);
    },
    onError,
  });
  const release = useMutation({
    mutationFn: () => releasePasswordReset(token, id),
    onSuccess: ({ request: next }) => {
      replace(next);
      backToList();
    },
    onError,
  });
  const issue = useMutation({
    mutationFn: () => issuePasswordResetLink(token, id),
    onSuccess: (link) => {
      setNotice(null);
      setIssued(link);
      replace(link.request);
    },
    onError,
  });
  const close = useMutation({
    mutationFn: (outcome: "reject" | "dismiss") =>
      outcome === "reject" ? rejectPasswordReset(token, id) : dismissPasswordReset(token, id),
    onSuccess: () => {
      remove();
      backToList();
    },
    onError,
  });
  const busy = claim.isPending || release.isPending || issue.isPending || close.isPending;

  // Opening a new or own request claims it (again, to keep the hold fresh).
  const state = request?.state;
  useEffect(() => {
    if (claimTried.current || !token || (state !== "open" && state !== "mine")) return;
    claimTried.current = true;
    claim.mutate();
  }, [state, token, claim]);

  const back = (
    <Link href="/password-resets" className="text-sm text-[var(--text-soft)]">
      ‹ {t("back")}
    </Link>
  );

  if (!request) {
    return (
      <div className="flex flex-col gap-4">
        {back}
        <p className="text-[var(--text-soft)]">{loading ? t("loading") : t("gone")}</p>
      </div>
    );
  }

  const person = request.person;
  const sources = sourceLabels(request, t);
  const mine = Boolean(currentUser?.id && request.claimed_by?.user_id === currentUser.id);
  const sender = currentUser?.nickname ?? "";

  return (
    <div className="flex flex-col gap-5">
      {back}
      <header className="flex items-start gap-3">
        <PersonAvatar name={person.display_name} url={person.avatar_url} size={56} />
        <div className="flex min-w-0 flex-col gap-0.5">
          <h1 className="truncate text-xl font-semibold text-[var(--text)]">{person.display_name}</h1>
          <p className="truncate text-sm text-[var(--dim)]">@{person.handle}</p>
          <p className="text-sm text-[var(--text-soft)]">
            {[sources.length ? t("via", { sources: sources.join(" · ") }) : null, t("requested", { time: relativeTime(request.requested_at, now, locale) })]
              .filter(Boolean)
              .join(" · ")}
          </p>
          <span className="mt-1">
            <StateChip request={request} now={now} />
          </span>
        </div>
      </header>

      {notice ? (
        <p role="alert" className="text-sm text-[var(--danger)]">
          {notice}
        </p>
      ) : null}

      {issued ? (
        <SendPanel
          link={issued}
          personName={person.display_name}
          personHandle={person.handle}
          sender={sender}
          onDone={backToList}
        />
      ) : request.state === "taken" ? (
        <section className="flex flex-col items-start gap-3">
          <p className="text-[var(--text-soft)]">{t("takenNotice", { name: claimerName(request, t) })}</p>
          {canTakeOver(request) ? (
            <button type="button" className={secondaryButton} disabled={busy} onClick={() => claim.mutate()}>
              {t("takeOver")}
            </button>
          ) : null}
        </section>
      ) : request.state === "expired" ? (
        <section className="flex flex-col items-start gap-3">
          <p className="text-[var(--text-soft)]">{t("expiredNotice")}</p>
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className={primaryButton} disabled={busy} onClick={() => issue.mutate()}>
              {issue.isPending ? t("creating") : t("sendNewLink")}
            </button>
            <button type="button" className={secondaryButton} disabled={busy} onClick={() => close.mutate("dismiss")}>
              {t("dismiss")}
            </button>
          </div>
        </section>
      ) : request.state === "link_sent" ? (
        <section className="flex flex-col items-start gap-3">
          <p className="text-[var(--text-soft)]">
            {request.link_expires_at
              ? mine
                ? t("linkSentNotice", { email: person.email ?? "", time: relativeTime(request.link_expires_at, now, locale) })
                : t("linkSentBy", { name: claimerName(request, t), time: relativeTime(request.link_expires_at, now, locale) })
              : t("stateLinkSentPlain")}
          </p>
          {mine || canTakeOver(request) ? (
            <button type="button" className={secondaryButton} disabled={busy} onClick={() => issue.mutate()}>
              {issue.isPending ? t("creating") : t("newLink")}
            </button>
          ) : null}
        </section>
      ) : (
        <section className="flex flex-col gap-4">
          <div className="rounded-2xl border border-[var(--border)] bg-[var(--panel)] p-4">
            <h2 className="font-semibold text-[var(--text)]">{t("checklistTitle")}</h2>
            <ol className="mt-3 flex list-decimal flex-col gap-2 ps-5 text-sm text-[var(--text-soft)]">
              <li>{t("checkCall")}</li>
              <li>{t("checkQuestion")}</li>
              <li>{person.email ? t("checkInbox", { email: person.email }) : t("checkInboxGeneric")}</li>
            </ol>
          </div>

          {confirmingReject ? (
            <div role="group" className="flex flex-col gap-3 rounded-2xl border border-[var(--border)] p-4">
              <p className="text-sm text-[var(--text)]">{t("rejectConfirm")}</p>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  className="rounded-full bg-[var(--danger)] px-4 py-2.5 text-sm font-semibold text-[var(--danger-contrast)] disabled:opacity-40"
                  disabled={busy}
                  onClick={() => close.mutate("reject")}
                >
                  {t("rejectYes")}
                </button>
                <button type="button" className={secondaryButton} disabled={busy} onClick={() => setConfirmingReject(false)}>
                  {t("cancel")}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                className={primaryButton}
                disabled={busy || request.state !== "mine"}
                onClick={() => issue.mutate()}
              >
                {issue.isPending ? t("creating") : t("createLink")}
              </button>
              <button
                type="button"
                className={secondaryButton}
                disabled={busy || request.state !== "mine"}
                onClick={() => release.mutate()}
              >
                {t("release")}
              </button>
              <button
                type="button"
                className="px-2 py-2.5 text-sm font-semibold text-[var(--dim)] underline-offset-4 hover:underline disabled:opacity-40"
                disabled={busy || request.state !== "mine"}
                onClick={() => setConfirmingReject(true)}
              >
                {t("reject")}
              </button>
            </div>
          )}
          {request.state === "open" && claim.isError ? (
            <button type="button" className={`${secondaryButton} self-start`} onClick={() => claim.mutate()}>
              {t("retry")}
            </button>
          ) : null}
        </section>
      )}
    </div>
  );
}
