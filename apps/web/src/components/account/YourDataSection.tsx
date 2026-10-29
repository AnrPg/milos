"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  dataExportRefusal,
  fetchDataExports,
  latestDataExport,
  requestDataExport,
  type DataExport,
} from "@/api/data-exports";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const EXPORTS_QUERY_KEY = ["account", "data-exports"] as const;
const PENDING_POLL_MS = 5000;

const primaryButton = { background: "var(--primary)", color: "var(--primary-contrast)" } as const;
const linkStyle = { color: "var(--primary)" } as const;

/**
 * Ρυθμίσεις › «Τα δεδομένα σου» (ADR-267): ask for a copy of everything
 * Palee keeps about this profile (one ZIP of JSON files), download it while
 * it is kept, and open the privacy policy and terms. Reachable as
 * /me/settings#your-data, the link of the "ready" email.
 */
export function YourDataSection() {
  const t = useTranslations("legal");
  const i18n = useUiTranslations();
  const format = useFormatter();
  const { tokens, currentUser } = useSession();
  const queryClient = useQueryClient();
  const [requesting, setRequesting] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const exportsQuery = useQuery({
    queryKey: [...EXPORTS_QUERY_KEY, currentUser?.id ?? null],
    queryFn: () => fetchDataExports(tokens!.access_token),
    enabled: Boolean(tokens?.access_token),
    // The file is built in the background: look again until it is there.
    refetchInterval: (query) =>
      latestDataExport(query.state.data as DataExport[] | undefined)?.status === "pending" ? PENDING_POLL_MS : false,
  });
  const latest = latestDataExport(exportsQuery.data);
  const date = (at: string | null | undefined) =>
    at ? format.dateTime(new Date(at), { dateStyle: "medium", timeStyle: "short" }) : "";
  const size = (bytes: number) =>
    bytes < 1_000_000
      ? format.number(Math.max(bytes / 1000, 1), { style: "unit", unit: "kilobyte", maximumFractionDigits: 0 })
      : format.number(bytes / 1_000_000, { style: "unit", unit: "megabyte", maximumFractionDigits: 1 });

  async function request() {
    if (!tokens || requesting) return;
    setRequesting(true);
    setError(null);
    setNotice(null);
    try {
      await requestDataExport(tokens.access_token);
      await queryClient.invalidateQueries({ queryKey: EXPORTS_QUERY_KEY });
    } catch (caught) {
      const refusal = dataExportRefusal(caught);
      if (refusal?.kind === "in_progress") setNotice(t("exportInProgress"));
      else if (refusal?.kind === "rate_limited" && refusal.retryAt) {
        setNotice(t("exportRateLimited", { date: date(refusal.retryAt) }));
      } else if (refusal?.kind === "rate_limited") setNotice(t("exportRateLimitedLater"));
      else setError(localizeError(caught, i18n));
    } finally {
      setRequesting(false);
    }
  }

  const pending = latest?.status === "pending";

  return (
    <CollapsibleSection id="your-data" title={t("yourDataTitle")} description={t("yourDataDescription")}>
      <div className="space-y-4">
        <div className="space-y-2">
          <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("downloadMyData")}
          </h3>
          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
            {t("downloadExplainer")}
          </p>
        </div>

        {latest ? <ExportStatus item={latest} date={date} size={size} /> : null}

        <button
          type="button"
          disabled={requesting || pending || !tokens}
          onClick={() => void request()}
          className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
          style={primaryButton}
        >
          {requesting ? t("requesting") : latest ? t("requestNewCopy") : t("downloadMyData")}
        </button>

        {notice ? (
          <p className="text-sm leading-6" role="status" style={{ color: "var(--text-soft)" }}>
            {notice}
          </p>
        ) : null}
        {error ? <ErrorNotice>{error}</ErrorNotice> : null}

        <p className="flex flex-wrap gap-x-5 gap-y-1 border-t pt-4 text-sm" style={{ borderColor: "var(--border)" }}>
          <Link href="/privacy" className="font-semibold" style={linkStyle}>
            {t("privacyTitle")}
          </Link>
          <Link href="/terms" className="font-semibold" style={linkStyle}>
            {t("termsTitle")}
          </Link>
        </p>
      </div>
    </CollapsibleSection>
  );
}

function ExportStatus({
  item,
  date,
  size,
}: {
  item: DataExport;
  date: (at: string | null | undefined) => string;
  size: (bytes: number) => string;
}) {
  const t = useTranslations("legal");
  const box = { background: "var(--panel-muted)", border: "1px solid var(--border)" } as const;

  if (item.status === "pending") {
    return (
      <p className="rounded-xl px-4 py-3 text-sm leading-6" role="status" style={{ ...box, color: "var(--text)" }}>
        {t("exportPending", { date: date(item.requested_at) })}
      </p>
    );
  }

  if (item.status === "failed") {
    return <ErrorNotice live="polite">{t("exportFailed")}</ErrorNotice>;
  }

  if (item.status === "expired" || !item.file?.download_url) {
    return (
      <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
        {t("exportExpired", { date: date(item.completed_at ?? item.requested_at) })}
      </p>
    );
  }

  return (
    <div className="space-y-2 rounded-xl px-4 py-3 text-sm" style={box}>
      <p style={{ color: "var(--text)" }}>{t("exportReady", { date: date(item.completed_at) })}</p>
      <a
        href={item.file.download_url}
        download={item.file.name}
        rel="noopener"
        className="inline-block font-semibold"
        style={linkStyle}
      >
        {t("downloadFile", { size: size(item.file.bytes) })}
      </a>
      {item.expires_at ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("exportAvailableUntil", { date: date(item.expires_at) })}
        </p>
      ) : null}
    </div>
  );
}
