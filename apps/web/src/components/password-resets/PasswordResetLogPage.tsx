"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { PASSWORD_RESET_LOG_KEY, fetchPasswordResetLog } from "@/api/password-resets";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const EVENTS = new Set([
  "requested",
  "claimed",
  "released",
  "link_issued",
  "completed",
  "rejected",
  "dismissed",
  "recovery_code_used",
]);

/** ADR-187: the vendor's security log of every password reset step, newest first. */
export function PasswordResetLogPage() {
  const t = useTranslations("passwordResets");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const log = useQuery({
    queryKey: PASSWORD_RESET_LOG_KEY,
    queryFn: () => fetchPasswordResetLog(token!),
    enabled: Boolean(token),
  });
  const forbidden = log.error instanceof ApiError && log.error.status === 403;
  const entries = log.data?.entries ?? [];
  const when = (iso: string) => new Date(iso).toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" });

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <Link href="/platform/organizations" className="text-sm text-[var(--text-soft)]">
          ‹ {t("logBack")}
        </Link>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("logTitle")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("logSubtitle")}</p>
        <p className="mt-2 text-sm text-[var(--dim)]">{t("logHint")}</p>
        <Link
          href="/password-resets"
          className="mt-3 self-start rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("logOpenRequests")}
        </Link>
      </header>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("logForbidden")}</p> : null}
      {log.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {log.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}
      {log.isSuccess && entries.length === 0 ? <p className="mt-6 text-[var(--text-soft)]">{t("logEmpty")}</p> : null}

      {entries.length > 0 ? (
        <table className="mt-4 w-full border-collapse text-sm">
          <thead className="sr-only sm:not-sr-only">
            <tr className="text-start text-xs font-bold uppercase tracking-[0.14em] text-[var(--dim)]">
              <th scope="col" className="py-2 pe-3 text-start font-bold">{t("logTime")}</th>
              <th scope="col" className="py-2 pe-3 text-start font-bold">{t("logEvent")}</th>
              <th scope="col" className="py-2 pe-3 text-start font-bold">{t("logAccount")}</th>
              <th scope="col" className="py-2 text-start font-bold">{t("logHandler")}</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((entry) => (
              <tr
                key={entry.id}
                className="grid grid-cols-2 gap-x-3 border-t border-[var(--border)] py-3 sm:table-row sm:py-0"
              >
                <td className="col-span-2 text-xs text-[var(--dim)] sm:py-3 sm:pe-3 sm:text-sm sm:whitespace-nowrap">
                  <time dateTime={entry.inserted_at}>{when(entry.inserted_at)}</time>
                </td>
                <td className="col-span-2 font-semibold text-[var(--text)] sm:py-3 sm:pe-3">
                  {EVENTS.has(entry.event) ? t(`event_${entry.event}`) : entry.event}
                </td>
                <td className="truncate text-[var(--text-soft)] sm:py-3 sm:pe-3">
                  {entry.handle ? `@${entry.handle}` : "—"}
                </td>
                <td className="truncate text-[var(--text-soft)] sm:py-3">
                  {entry.handler_handle ? (
                    <>
                      <span className="sm:hidden">{t("logBy")} </span>@{entry.handler_handle}
                    </>
                  ) : (
                    "—"
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
    </main>
  );
}
