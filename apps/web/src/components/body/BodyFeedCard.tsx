"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";

import type { TypedJournalItem } from "@/api/journal";
import { snapshotSummary } from "@/components/body/BodyPage";
import { useBodySettings } from "@/components/body/use-body";

/**
 * A Μέτρηση in Ροή (ADR-158 §6): only ever in the member's own feed; the
 * values follow the weight display choice (the server already left out what
 * must not show), the photos are only counted.
 */
export function BodyFeedCard({
  item,
  locale,
  badge,
}: {
  item: Extract<TypedJournalItem, { kind: "body" }>;
  locale: string;
  badge: ReactNode;
}) {
  const t = useTranslations("Body");
  const tJournal = useTranslations("MemberApp.journal");
  const settings = useBodySettings();
  const time = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(item.occurred_at));
  return (
    <li className="flex flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="journal-body-entry">
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {tJournal("kind.body")} · <time dateTime={item.occurred_at}>{time}</time>
      </p>
      <Link href={`/journal/body/${item.entry.id}`} className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>
        {snapshotSummary(item.entry, { catalog: settings.data?.catalog ?? [] }, locale, t)}
      </Link>
      <div>{badge}</div>
    </li>
  );
}
