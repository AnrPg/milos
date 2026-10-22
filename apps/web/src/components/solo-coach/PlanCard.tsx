"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { ADMIN_PLAN_KEY, fetchAdminPlan, type OrganizationPlan } from "@/api/platform-plans";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatCents, shownMonthlyPrice, usageShare, usageTone, type UsageTone } from "@/lib/solo-coach";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

const TONE_COLOR: Record<UsageTone, string> = {
  ok: "var(--primary)",
  warn: "var(--warning)",
  full: "var(--danger)",
};

export function useAdminPlan(token: string | undefined) {
  return useQuery({
    queryKey: ADMIN_PLAN_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchAdminPlan(token!),
    staleTime: 5 * 60_000,
    // A member of staff without settings rights gets 403: nothing to show.
    retry: (count, error) => !(error instanceof ApiError && error.status === 403) && count < 2,
  });
}

/**
 * The organization's Palee plan (ADR-170), for owners and admins: name,
 * status, seats used against the limits and the price once it is confirmed.
 */
export function PlanCard({ token }: { token: string }) {
  const t = useTranslations("SoloCoach");
  const locale = useUiLocale();
  const plan = useAdminPlan(token);
  const data = plan.data;
  if (!data?.plan) {
    return plan.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("plan.loading")}</p> : null;
  }

  const price =
    data.price_override_cents != null
      ? formatCents(data.price_override_cents, data.plan.currency, locale)
      : shownMonthlyPrice(data.plan, locale);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-lg font-bold" style={{ color: "var(--text)" }}>{data.plan.name}</p>
        {data.status ? (
          <span className="rounded-full px-3 py-1 text-xs font-semibold" style={data.status === "active" ? SPARK_ACTIVE_STYLE : { background: "var(--panel-muted)", color: "var(--text-soft)" }}>
            {t(`plan.status.${data.status}`)}
          </span>
        ) : null}
      </div>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {[
          data.trial_days_left != null ? t("plan.trialLeft", { days: data.trial_days_left }) : null,
          price ? t("plan.price", { price }) : t("plan.priceSoon"),
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
      <ul className="flex flex-col gap-3">
        {(data.usage ?? []).map((row) => {
          const share = usageShare(row);
          const tone = usageTone(row);
          return (
            <li key={row.key}>
              <div className="flex justify-between text-sm" style={{ color: "var(--text)" }}>
                <span>{t(`plan.limit.${row.key}`)}</span>
                <span className="tabular-nums" style={{ color: tone === "ok" ? "var(--text-soft)" : TONE_COLOR[tone] }}>
                  {row.limit == null ? t("plan.unlimited", { used: row.used }) : t("plan.used", { used: row.used, limit: row.limit })}
                </span>
              </div>
              {share != null ? (
                <div className="mt-1 h-1.5 overflow-hidden rounded-full" style={{ background: "var(--border)" }} role="presentation">
                  <div className="h-full rounded-full" style={{ width: `${Math.round(share * 100)}%`, background: TONE_COLOR[tone] }} />
                </div>
              ) : null}
            </li>
          );
        })}
      </ul>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("plan.contact")}</p>
    </div>
  );
}

/** The one line an owner should not miss: a trial ending or over, a late payment, a full plan. */
export function PlanNotice({ token }: { token: string }) {
  const t = useTranslations("SoloCoach");
  const plan = useAdminPlan(token);
  const message = planNoticeMessage(plan.data, t);
  if (!message) return null;
  return (
    <p
      role="status"
      className="rounded-2xl px-4 py-3 text-sm"
      style={{
        background: "color-mix(in srgb, var(--warning) 12%, transparent)",
        border: "1px solid color-mix(in srgb, var(--warning) 35%, transparent)",
        color: "var(--text)",
      }}
    >
      {message}
    </p>
  );
}

function planNoticeMessage(
  data: OrganizationPlan | undefined,
  t: ReturnType<typeof useTranslations>,
): string | null {
  // A partial answer (an older API, a proxy error page) shows no notice rather than breaking Settings.
  if (!data?.plan) return null;
  if (data.notice === "trial_ending") return t("plan.notice.trial_ending", { days: data.trial_days_left ?? 0 });
  if (data.notice) return t(`plan.notice.${data.notice}`);
  const fullStaff = (data.usage ?? []).find((row) => row.key === "staff_seats" && usageTone(row) === "full");
  return fullStaff ? t("plan.notice.staff_full") : null;
}
