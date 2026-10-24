"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { PersonAvatar } from "@/components/social/PersonAvatar";

import { CountBadge } from "./BuddyBits";
import { overviewLists, personName } from "./buddy-model";
import { useBuddies } from "./use-buddies";

/**
 * Μηνύματα: the buddy conversations beside the gym threads (ADR-160 §6),
 * each with its unread count. Nothing shows without a buddy conversation.
 */
export function BuddyThreads({ onNavigate }: { onNavigate?: () => void } = {}) {
  const t = useTranslations("Buddy");
  const overview = useBuddies();
  const { buddies, supporting } = overviewLists(overview.data);
  const links = [...buddies, ...supporting].filter((link) => link.started_at && link.person);
  if (links.length === 0) return null;
  return (
    <section aria-label={t("threadsTitle")} className="flex flex-col gap-2" data-testid="buddy-threads">
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("threadsTitle")}</p>
      <ul className="flex flex-col gap-2">
        {links.map((link) => {
          const name = personName(link.person, t("someone"));
          const unread = link.unread_messages ?? 0;
          return (
            <li key={link.id}>
              <Link
                href={`/me/buddy/${encodeURIComponent(link.id)}/chat`}
                onClick={onNavigate}
                className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-4 py-2"
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              >
                <span className="flex min-w-0 items-center gap-3">
                  <PersonAvatar name={name} url={link.person?.avatar_url} size={32} />
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
                    <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
                      {link.role === "requester" ? t("threadMyBuddy") : t("threadISupport")}
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
