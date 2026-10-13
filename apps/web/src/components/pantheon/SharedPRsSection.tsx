"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { PRSupportingMetrics, PRUnit } from "@/api/gamification";
import { fetchPRsSharedWithMe, type SharedPR } from "@/api/pr-sharing";
import { formatScore } from "@/components/pantheon/PantheonCard";
import { formatPRCardDetails } from "@/components/pantheon/pr-card-details";
import { useSession } from "@/components/session-provider";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

/** ADR-129: read-only PRs other accounts explicitly shared with me. */
export function SharedPRsSection() {
  const t = useTranslations("PrSharing");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;

  const sharedQuery = useQuery({
    queryKey: ["pr-sharing", "shared-with-me"],
    enabled: Boolean(token),
    queryFn: () => fetchPRsSharedWithMe(token!),
  });

  const shared = sharedQuery.data?.shared ?? [];

  return (
    <section className="space-y-4" aria-labelledby="shared-prs-title">
      <div>
        <h2 id="shared-prs-title" className="text-xl font-black" style={{ color: "var(--text)" }}>
          {t("sharedWithMeTitle")}
        </h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("sharedWithMeDescription")}</p>
      </div>

      {sharedQuery.isError ? (
        <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("loadError")}</p>
      ) : shared.length === 0 ? (
        sharedQuery.isPending ? null : (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("sharedWithMeEmpty")}</p>
        )
      ) : (
        shared.map((collection) => (
          <div
            key={collection.grant_id}
            className="space-y-3 rounded-[1.8rem] p-5"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>
              {t("sharedBy", { name: collection.owner.display_nickname })}
            </p>
            {collection.prs.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--dim)" }}>{t("ownerHasNoPrs")}</p>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                {collection.prs.map((pr) => <SharedPRCard key={pr.id} pr={pr} />)}
              </div>
            )}
          </div>
        ))
      )}
    </section>
  );
}

function SharedPRCard({ pr }: { pr: SharedPR }) {
  const t = useTranslations("PrSharing");
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const unit = pr.unit as PRUnit;
  const details = formatPRCardDetails((pr.supporting_metrics ?? {}) as PRSupportingMetrics, i18n);
  const date = new Date(pr.beaten_on).toLocaleDateString(uiLocale, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });

  return (
    <div className="rounded-[1.4rem] px-5 py-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <p className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{pr.name}</p>
      <div className="mt-1.5 flex items-baseline gap-1.5">
        <span className="text-2xl font-bold tabular-nums" style={{ color: "var(--primary)" }}>
          {formatScore(Number(pr.current_score), unit)}
        </span>
        <span className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
          {semanticLabel(unit, i18n)}
        </span>
      </div>
      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{date}</p>
      {details ? <p className="mt-2 text-[11px]" style={{ color: "var(--text-soft)" }}>{details}</p> : null}
      {pr.notes ? <p className="mt-1 text-[11px]" style={{ color: "var(--muted)" }}>{pr.notes}</p> : null}
      {pr.history.length > 0 ? (
        <p className="mt-2 text-[11px]" style={{ color: "var(--muted)" }}>
          {t("earlierResults", { count: pr.history.length })}
        </p>
      ) : null}
    </div>
  );
}
