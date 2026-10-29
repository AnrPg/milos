"use client";

import { useMemo } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchMyToday, MY_TODAY_KEY, type TodayItem } from "@/api/providers";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine } from "@/components/community/Sheet";
import { HubCard } from "@/components/member-app/HubParts";
import { localIsoDate } from "@/components/member-app/box/today-training";
import { SourceLabel } from "@/components/providers/SourceLabel";
import { useMyProviders, useSourceDirectory, useSwitchProvider } from "@/components/providers/use-providers";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { formatClock } from "@/lib/clock";

/** Where an item of «Σήμερα» opens inside Box, once its provider is selected. */
export function todayItemHref(item: Pick<TodayItem, "kind" | "id">) {
  switch (item.kind) {
    case "class":
      return `/box/schedule?open_slot=${encodeURIComponent(item.id)}`;
    case "appointment":
      return "/box/appointments";
    case "program":
      return `/box/workouts?open_assignment=${encodeURIComponent(item.id)}`;
    default:
      return "/box";
  }
}

function zone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

/**
 * «Σήμερα» across providers (board 17 Q2): the top card of Box lists today
 * from every provider in time order (untimed programme and WOD first), each
 * with its source. An item from another provider switches Box to it. With a
 * single provider Box's own today card already says it all, so this card is
 * not shown.
 */
export function TodayAcrossCard() {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const router = useRouter();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const providers = useMyProviders();
  const directory = useSourceDirectory();
  const { switchTo, pending, error } = useSwitchProvider();
  const date = useMemo(() => localIsoDate(new Date()), []);
  const timezone = useMemo(() => zone(), []);
  const multiple = (providers.data?.providers?.length ?? 0) > 1;
  const today = useQuery({
    queryKey: [...MY_TODAY_KEY, date, timezone],
    enabled: Boolean(token) && multiple,
    queryFn: () => fetchMyToday(token!, date, timezone),
    staleTime: 60_000,
  });

  if (!multiple) return null;

  const selectedId = providers.data?.selected_organization_id ?? null;
  const failed = (today.data?.failed_organization_ids ?? [])
    .map((id) => directory.active.get(id)?.name)
    .filter((name): name is string => Boolean(name));
  // Nothing today anywhere: no card (vision §4.2, §8.5).
  if (today.isSuccess && !today.data.items?.length && failed.length === 0) return null;

  async function open(item: TodayItem) {
    const href = todayItemHref(item);
    if (item.target.organization_id === selectedId) return router.push(href);
    if (await switchTo({ organization_id: item.target.organization_id, slug: item.target.slug })) router.push(href);
  }

  return (
    <HubCard eyebrow={t("todayTitle")}>
      {today.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : today.isError ? (
        <ErrorLine message={clientErrorMessage(today.error, i18n)} />
      ) : !today.data.items?.length ? null : (
        <ul className="flex flex-col" aria-label={t("todayTitle")}>
          {today.data.items.map((item) => (
            <li key={`${item.kind}:${item.id}`} style={{ borderBottom: "1px solid var(--border)" }} className="last:border-0">
              <button
                type="button"
                onClick={() => void open(item)}
                disabled={pending !== null}
                className="flex min-h-12 w-full items-center justify-between gap-3 py-2 text-start disabled:opacity-60"
              >
                <span className="min-w-0">
                  <span className="block truncate text-sm font-bold" style={{ color: "var(--text)" }}>
                    {item.at ? (
                      <time dateTime={item.at} className="tabular-nums">
                        {formatClock(new Date(item.at), locale, { hour: "2-digit", minute: "2-digit" })}
                        {" · "}
                      </time>
                    ) : null}
                    {item.title?.trim() || t(`todayKind.${item.kind}`)}
                  </span>
                  <span className="block text-xs" style={{ color: "var(--dim)" }}>
                    {t(`todayKind.${item.kind}`)}
                    {item.status && t.has(`todayStatus.${item.status}`) ? ` · ${t(`todayStatus.${item.status}`)}` : ""}
                  </span>
                </span>
                <SourceLabel source={item.source} directory={directory} always />
              </button>
            </li>
          ))}
        </ul>
      )}
      {failed.length > 0 ? (
        <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("todayPartial", { names: failed.join(", ") })}</p>
      ) : null}
      <ErrorLine message={error ? clientErrorMessage(error, i18n) : null} />
    </HubCard>
  );
}
