"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";

import {
  PASSWORD_RESETS_KEY,
  fetchPasswordResets,
  hidePasswordReset,
  type PasswordResetInbox,
  type PasswordResetRequest,
} from "@/api/password-resets";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { RequestView } from "@/components/password-resets/RequestView";
import { StateChip } from "@/components/password-resets/StateChip";
import { relativeTime } from "@/components/password-resets/reset-email";
import { sourceLabels } from "@/components/password-resets/request-labels";
import { useNow } from "@/components/password-resets/use-now";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** Re-reads the list while it is open, so claims by others show up. */
const POLL_MS = 30_000;

/**
 * ADR-187: the password reset requests the signed-in person can handle
 * (vendor, box owner/admin/front desk, the person's coach). `?request=<id>`
 * opens one directly, as the notification does.
 */
export function PasswordResetsPage() {
  const t = useTranslations("passwordResets");
  const pr = useTranslations("passwordReset");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const searchParams = useSearchParams();
  const openId = searchParams.get("request");
  const inbox = useQuery({
    queryKey: PASSWORD_RESETS_KEY,
    queryFn: () => fetchPasswordResets(token!),
    enabled: Boolean(token),
    refetchInterval: POLL_MS,
    refetchOnWindowFocus: true,
  });

  if (openId) {
    return (
      <main className="mx-auto w-full max-w-2xl px-4 py-6 sm:px-6">
        <RequestView
          key={openId}
          id={openId}
          request={inbox.data?.requests.find((request) => request.id === openId) ?? null}
          loading={inbox.isPending}
        />
      </main>
    );
  }

  const requests = inbox.data?.requests ?? [];

  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-6 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-4">
        <h1 className="text-2xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
        <p className="mt-1 text-sm text-[var(--dim)]">{pr("handlerNote")}</p>
      </header>

      {inbox.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}
      {inbox.isError ? (
        <ErrorNotice
          className="mt-6"
          action={
            <button type="button" className="font-semibold underline" onClick={() => void inbox.refetch()}>
              {t("retry")}
            </button>
          }
        >
          {t("loadError")}
        </ErrorNotice>
      ) : null}
      {inbox.isSuccess && requests.length === 0 ? <p className="mt-6 text-[var(--text-soft)]">{t("empty")}</p> : null}

      {requests.length > 0 ? (
        <ul className="mt-2 flex flex-col divide-y divide-[var(--border)]">
          {requests.map((request) => (
            <RequestRow key={request.id} request={request} />
          ))}
        </ul>
      ) : null}
    </main>
  );
}

function RequestRow({ request }: { request: PasswordResetRequest }) {
  const t = useTranslations("passwordResets");
  const locale = useLocale();
  const now = useNow();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const hide = useMutation({
    mutationFn: () => hidePasswordReset(tokens!.access_token, request.id),
    onSuccess: () =>
      queryClient.setQueryData<PasswordResetInbox>(PASSWORD_RESETS_KEY, (current) =>
        current ? { ...current, requests: current.requests.filter((entry) => entry.id !== request.id) } : current,
      ),
  });
  const sources = sourceLabels(request, t);
  const name = request.person.display_name;

  return (
    <li className="flex items-start gap-1 py-3">
      <Link
        href={`/password-resets?request=${encodeURIComponent(request.id)}`}
        className="flex min-w-0 flex-1 items-start gap-3 rounded-xl py-1 pe-1 transition-colors hover:bg-[var(--panel-muted)]"
      >
        <PersonAvatar name={name} url={request.person.avatar_url} size={44} />
        <span className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="flex min-w-0 flex-wrap items-baseline gap-x-2">
            <span className="truncate font-semibold text-[var(--text)]">{name}</span>
            <span className="truncate text-sm text-[var(--dim)]">@{request.person.handle}</span>
          </span>
          <span className="text-sm text-[var(--text-soft)]">
            {[sources.length ? t("via", { sources: sources.join(" · ") }) : null, t("requested", { time: relativeTime(request.requested_at, now, locale) })]
              .filter(Boolean)
              .join(" · ")}
          </span>
          <span className="mt-1">
            <StateChip request={request} now={now} />
          </span>
          {hide.isError ? <ErrorNotice variant="text">{t("hideError")}</ErrorNotice> : null}
        </span>
      </Link>
      <button
        type="button"
        disabled={hide.isPending}
        onClick={() => hide.mutate()}
        aria-label={t("hideNamed", { name })}
        title={t("hide")}
        className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-[var(--dim)] transition-colors hover:bg-[var(--panel-muted)] hover:text-[var(--text-soft)] disabled:opacity-40"
      >
        <svg aria-hidden="true" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M3 3l18 18" />
          <path d="M10.6 10.6a2 2 0 0 0 2.8 2.8" />
          <path d="M9.9 5.1A10.4 10.4 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2" />
          <path d="M6.6 6.6C3.9 8.4 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6" />
        </svg>
      </button>
    </li>
  );
}
