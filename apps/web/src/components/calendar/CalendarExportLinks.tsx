"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useMemo, useState } from "react";

import {
  fetchCalendarExportLinks,
  regenerateCalendarExportLinks,
  type CalendarExportLinks as CalendarExportLinksPayload,
} from "@/api/calendar";

type Props = {
  token: string | null | undefined;
  compact?: boolean;
};

export function CalendarExportLinks({ token, compact = false }: Props) {
  const i18n = useUiTranslations();
  const [links, setLinks] = useState<CalendarExportLinksPayload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [regenerating, setRegenerating] = useState(false);

  useEffect(() => {
    if (!token) return;

    let cancelled = false;

    void fetchCalendarExportLinks(token)
      .then((payload) => {
        if (!cancelled) {
          setLinks(payload);
          setError(null);
        }
      })
      .catch((requestError) => {
        if (!cancelled) setError(requestError instanceof Error ? requestError.message : i18n("calendarLinksUnavailabledc879c1"));
      });

    return () => {
      cancelled = true;
    };
  }, [i18n, token]);

  const sameOriginLinks = useMemo(() => {
    if (!links || typeof window === "undefined") return links;

    const httpsUrl = (window.location.origin) + (links.path);
    const webcalUrl = httpsUrl.replace(/^https?:\/\//, "webcal://");

    return {
      ...links,
      https_url: httpsUrl,
      webcal_url: webcalUrl,
      download_url: (httpsUrl) + "&download=1",
    };
  }, [links]);

  async function copyLink() {
    if (!sameOriginLinks) return;

    await navigator.clipboard.writeText(sameOriginLinks.https_url);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1400);
  }

  async function regenerateLinks() {
    if (!token) return;

    setRegenerating(true);
    setError(null);

    try {
      const payload = await regenerateCalendarExportLinks(token);
      setLinks(payload);
      setCopied(false);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : i18n("calendarLinksUnavailabledc879c1"));
    } finally {
      setRegenerating(false);
    }
  }

  if (!token) return null;

  return (
    <section
      className={compact ? "rounded-[1.5rem] p-4" : "rounded-[2rem] p-5"}
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.22em] text-[var(--primary)]">{i18n("calendarExport90a0627")}</p>
          <p className="mt-1 text-sm font-semibold text-[var(--text-soft)]">
            {i18n("subscribeForAutomaticUpdatesCopyTheHttpsIcsed663fe")}
          </p>
          {error ? <p className="mt-2 text-xs font-bold text-[var(--primary-strong)]">{error}</p> : null}
        </div>

        <div className="flex flex-wrap gap-2">
          <a
            className="rounded-full px-4 py-2 text-sm font-bold"
            href={sameOriginLinks?.webcal_url ?? "#"}
            style={{ background: "var(--text)", color: "var(--bg)" }}
          >
            {i18n("subscribed6981f7")}
          </a>
          <button
            className="rounded-full px-4 py-2 text-sm font-bold"
            disabled={!sameOriginLinks}
            onClick={() => void copyLink()}
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            type="button"
          >
            {copied ? i18n("copied8e3df45") : i18n("copyLink2f84eea")}
          </button>
          <a
            className="rounded-full px-4 py-2 text-sm font-bold"
            href={sameOriginLinks?.download_url ?? "#"}
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("downloadIcs58ede50")}
          </a>
          <button
            className="rounded-full px-4 py-2 text-sm font-bold disabled:opacity-50"
            disabled={!sameOriginLinks || regenerating}
            onClick={() => void regenerateLinks()}
            style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", color: "var(--primary)" }}
            type="button"
          >
            {regenerating ? i18n("regenerating07e5b0f") : i18n("regenerateLink8bf2f06")}
          </button>
        </div>
      </div>

      {sameOriginLinks ? (
        <div className="mt-4 grid gap-2 text-xs font-semibold text-[var(--muted)] md:grid-cols-2 xl:grid-cols-4">
          <p>{sameOriginLinks.help.google}</p>
          <p>{sameOriginLinks.help.apple}</p>
          <p>{sameOriginLinks.help.outlook}</p>
          <p>{sameOriginLinks.help.download}</p>
        </div>
      ) : (
        <p className="mt-4 text-xs font-semibold text-[var(--muted)]">{i18n("loadingCalendarLinks1dad320")}</p>
      )}
    </section>
  );
}
