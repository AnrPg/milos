"use client";

import Link from "next/link";
import { Fragment } from "react";
import { useTranslations } from "next-intl";

import type { FollowGroups } from "@/api/social";

import { countsParts } from "./social-model";

/**
 * The line under a name (ADR-193 §1), Buddies first, three groups that never
 * overlap. On Εγώ (`mine`) each part opens its Connections tab; on someone
 * else's profile it is plain text, since their lists aren't yours to open.
 */
export function CountsLine({
  groups,
  mine,
  centered = false,
}: {
  groups: FollowGroups | null | undefined;
  mine: boolean;
  centered?: boolean;
}) {
  const t = useTranslations("Social");
  return (
    <p
      className={`flex flex-wrap items-center gap-x-1.5 text-sm ${centered ? "justify-center" : ""}`}
      style={{ color: mine ? "var(--text)" : "var(--text-soft)" }}
    >
      {countsParts(groups, mine).map((part, index) => (
        <Fragment key={part.tab}>
          {index > 0 ? <span aria-hidden="true" style={{ color: "var(--dim)" }}>·</span> : null}
          {mine ? (
            <Link href={`/me/connections?tab=${part.tab}`} className="inline-flex min-h-11 items-center font-semibold">
              {t(part.key, { count: part.count })}
            </Link>
          ) : (
            <span>{t(part.key, { count: part.count })}</span>
          )}
        </Fragment>
      ))}
    </p>
  );
}

/** «Buddy»: you follow each other. A quiet pill, shown only where it adds something. */
export function BuddyBadge() {
  const t = useTranslations("Social");
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold"
      style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--text)" }}
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="9" cy="8" r="3.5" />
        <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
        <path d="M16 4.5a3.5 3.5 0 0 1 0 7" />
        <path d="M18.5 14a6.5 6.5 0 0 1 3 6" />
      </svg>
      {t("buddyBadge")}
    </span>
  );
}

/** What a tab holds back until you follow (a `Social` key from `postsLockKey`), with a padlock. */
export function LockedNote({ textKey }: { textKey: string }) {
  const t = useTranslations("Social");
  return (
    <p className="flex items-center gap-3 rounded-3xl p-4 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" className="shrink-0">
        <rect width="18" height="11" x="3" y="11" rx="2" />
        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
      </svg>
      {t(textKey)}
    </p>
  );
}
