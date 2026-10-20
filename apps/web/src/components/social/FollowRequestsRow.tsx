"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { useSocialSummary } from "@/components/social/use-social";

/** «Αιτήματα ακολούθησης (n)» at the top of the inbox (plan §5a Q11); hidden when there are none. */
export function FollowRequestsRow({ onNavigate }: { onNavigate?: () => void }) {
  const t = useTranslations("Social");
  const summary = useSocialSummary();
  const count = summary.data?.requests_count ?? 0;
  if (count === 0) return null;
  return (
    <Link
      href="/me/follow-requests"
      onClick={onNavigate}
      className="mt-5 flex min-h-12 items-center justify-between gap-3 rounded-[1.2rem] px-4 py-3"
      style={{ border: "1px solid var(--border)", background: "var(--panel-muted)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("requestsRow", { count })}</span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>{t("requestsRowHint")}</span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </Link>
  );
}
