"use client";

import { useEffect, useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BUDDIES_KEY, createBuddyInviteLink, fetchBuddyCandidates, inviteBuddy, type BuddyCandidate } from "@/api/buddies";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { key, personName } from "./buddy-model";
import { buddyErrorMessage } from "./errors";
import { useBuddyToken } from "./use-buddies";

/** The page a buddy link opens on this site. */
export function buddyInviteUrl(token: string): string {
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  return `${origin}/buddy/${encodeURIComponent(token)}`;
}

/**
 * «Πρόσθεσε άτομο ή τον coach» (board 15 q2 A): your coach, people of your
 * clubs and people you follow, or a link for someone not on Milos yet,
 * shared through the phone's share sheet (copied where there is none).
 * Nothing starts until they accept; a link expires after a week.
 */
export function AddBuddySheet({ onClose, inviteDays }: { onClose: () => void; inviteDays: number }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const labelId = useId();
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const [term, setTerm] = useState("");
  const [debounced, setDebounced] = useState("");
  const [shared, setShared] = useState<{ url: string; copied: boolean } | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(term.trim()), 250);
    return () => clearTimeout(timer);
  }, [term]);

  const candidates = useQuery({
    queryKey: [...BUDDIES_KEY, "candidates", debounced],
    enabled: Boolean(token),
    queryFn: () => fetchBuddyCandidates(token!, debounced),
    staleTime: 30_000,
  });

  const invite = useMutation({
    mutationFn: (userId: string) => inviteBuddy(token!, userId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY });
    },
  });

  const link = useMutation({
    mutationFn: () => createBuddyInviteLink(token!),
    onSuccess: async (data) => {
      void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY });
      const url = buddyInviteUrl(data.token);
      const payload = { title: t("shareTitle"), text: t("shareText"), url };
      try {
        if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
          await navigator.share(payload);
          setShared({ url, copied: false });
          return;
        }
      } catch {
        // Dismissed or refused: fall through to copying.
      }
      let copied = false;
      try {
        await navigator.clipboard.writeText(url);
        copied = true;
      } catch {
        copied = false;
      }
      setShared({ url, copied });
    },
  });

  const list = candidates.data ?? [];
  const invited = invite.variables && invite.isSuccess ? invite.variables : null;

  return (
    <Sheet labelId={labelId} title={t("addTitle")} onClose={onClose} footer={<SheetButton onClick={onClose}>{t("close")}</SheetButton>}>
      <div className="flex flex-col gap-4">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("addIntro")}</p>
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("searchLabel")}
          <input
            type="search"
            value={term}
            onChange={(event) => setTerm(event.target.value)}
            placeholder={t("searchPlaceholder")}
            className="min-h-11 rounded-2xl px-4"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
        {candidates.isPending ? (
          <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : list.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{debounced.length >= 2 ? t("searchEmpty") : t("searchHint")}</p>
        ) : (
          <ul className="flex flex-col gap-2" data-testid="buddy-candidates">
            {list.map((candidate) => (
              <CandidateRow
                key={candidate.person?.id ?? candidate.relation}
                candidate={candidate}
                busy={invite.isPending && invite.variables === candidate.person?.id}
                justInvited={invited === candidate.person?.id}
                onInvite={() => candidate.person && invite.mutate(candidate.person.id)}
              />
            ))}
          </ul>
        )}
        <ErrorLine message={buddyErrorMessage(invite.error, t, tUi)} />

        <div className="flex flex-col gap-2 border-t pt-4" style={{ borderColor: "var(--border)" }}>
          <button
            type="button"
            onClick={() => link.mutate()}
            disabled={link.isPending}
            className="flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
              <path d="M12 3v12M7 8l5-5 5 5M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" />
            </svg>
            {t("sendLink")}
          </button>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("sendLinkHint", { days: inviteDays })}</p>
          {shared ? (
            <div className="flex flex-col gap-2" role="status">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {shared.copied ? t("linkCopied") : t("linkReady")}
              </p>
              <input
                readOnly
                value={shared.url}
                aria-label={t("linkLabel")}
                onFocus={(event) => event.currentTarget.select()}
                className="min-h-11 rounded-2xl px-4 text-sm"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                data-testid="buddy-invite-url"
              />
            </div>
          ) : null}
          <ErrorLine message={buddyErrorMessage(link.error, t, tUi)} />
        </div>
      </div>
    </Sheet>
  );
}

function CandidateRow({
  candidate,
  busy,
  justInvited,
  onInvite,
}: {
  candidate: BuddyCandidate;
  busy: boolean;
  justInvited: boolean;
  onInvite: () => void;
}) {
  const t = useTranslations("Buddy");
  const name = personName(candidate.person, t("someone"));
  const status = justInvited ? "pending" : candidate.link_status;
  return (
    <li className="flex items-center justify-between gap-3 rounded-2xl px-3 py-2" style={{ background: "var(--panel-raised)" }}>
      <span className="flex min-w-0 items-center gap-3">
        <PersonAvatar name={name} url={candidate.person?.avatar_url} size={36} />
        <span className="min-w-0">
          <span className="block truncate text-sm font-bold" style={{ color: "var(--text)" }}>{name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>{t(key("relation", candidate.relation))}</span>
        </span>
      </span>
      {status ? (
        <span className="shrink-0 text-xs font-semibold" style={{ color: "var(--dim)" }}>{t(key("candidateStatus", status))}</span>
      ) : (
        <button
          type="button"
          onClick={onInvite}
          disabled={busy}
          aria-label={t("inviteName", { name })}
          className="min-h-9 shrink-0 rounded-full px-3 text-xs font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {t("invite")}
        </button>
      )}
    </li>
  );
}
