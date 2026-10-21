"use client";

import Link from "next/link";
import { useState } from "react";
import { useInfiniteQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  acceptFollowRequest,
  declineFollowRequest,
  fetchFollowRequests,
  REQUESTS_KEY,
  SOCIAL_KEY,
  type FollowEntry,
} from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { BookingSharingOffer } from "@/components/social/BookingSharing";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

/** «Αιτήματα ακολούθησης» (plan §5a Q11): accept or decline, newest first. */
export function FollowRequestsPage() {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const requests = useInfiniteQuery({
    queryKey: REQUESTS_KEY,
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchFollowRequests(token!, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const entries = requests.data?.pages.flatMap((page) => page.entries) ?? [];

  return (
    <HubPage title={t("requestsTitle")}>
      <BookingSharingOffer />
      {requests.isPending ? <p style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {requests.isSuccess && entries.length === 0 ? (
        <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {t("requestsEmpty")}
        </p>
      ) : null}
      <ul className="flex flex-col gap-2">
        {entries.map((entry) => (
          <RequestRow key={entry.follow_id} entry={entry} />
        ))}
      </ul>
      {requests.hasNextPage ? (
        <button
          type="button"
          onClick={() => void requests.fetchNextPage()}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("more")}
        </button>
      ) : null}
    </HubPage>
  );
}

function RequestRow({ entry }: { entry: FollowEntry }) {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const person = entry.person;
  if (!person) return null;

  async function run(action: () => Promise<void>) {
    if (!token || busy) return;
    setBusy(true);
    setError(null);
    try {
      await action();
      await queryClient.invalidateQueries({ queryKey: SOCIAL_KEY });
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
      setBusy(false);
    }
  }

  return (
    <li className="flex flex-col gap-2 rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-center gap-3">
        <Link href={`/people/${person.id}`} className="flex min-w-0 flex-1 items-center gap-3">
          <PersonAvatar name={person.nickname} url={person.avatar_url} />
          <span className="truncate font-bold" style={{ color: "var(--text)" }}>{person.nickname ?? "?"}</span>
        </Link>
        <button
          type="button"
          disabled={busy}
          onClick={() => void run(() => declineFollowRequest(token!, entry.follow_id))}
          className="min-h-11 rounded-2xl px-3 text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("decline")}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => void run(() => acceptFollowRequest(token!, entry.follow_id))}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {t("accept")}
        </button>
      </div>
      {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </li>
  );
}
