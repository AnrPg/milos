"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { CountBadge } from "@/components/buddy/BuddyBits";
import { PersonAvatar } from "@/components/social/PersonAvatar";

import { sortMatches } from "./partners-model";
import { usePartnerMatches } from "./use-partners";

/**
 * Μηνύματα › Partners (ADR-169 §7, ADR-280): each match's conversation,
 * active first, with its unread count. Nothing shows without a match.
 */
export function PartnerThreads({ onNavigate }: { onNavigate?: () => void }) {
  const t = useTranslations("Partners");
  const matches = usePartnerMatches();
  const rows = sortMatches(matches.data ?? []);
  if (rows.length === 0) return null;
  return (
    <section aria-label={t("threadsTitle")} className="flex flex-col gap-2" data-testid="partner-threads">
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("threadsTitle")}</p>
      <ul className="flex flex-col gap-2">
        {rows.map((match) => {
          const name = match.person.nickname ?? t("someone");
          const unread = match.unread ?? 0;
          return (
            <li key={match.id}>
              <Link
                href={`/partners/${encodeURIComponent(match.id)}`}
                onClick={onNavigate}
                className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-4 py-2"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", opacity: match.status === "active" ? 1 : 0.7 }}
              >
                <span className="flex min-w-0 items-center gap-3">
                  <PersonAvatar name={name} url={match.person.avatar_url} size={32} />
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
                    <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
                      {match.status === "active" ? t("threadSubtitle") : t("threadEnded")}
                    </span>
                  </span>
                </span>
                <CountBadge count={unread} label={t("unreadCount", { count: unread })} />
              </Link>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
