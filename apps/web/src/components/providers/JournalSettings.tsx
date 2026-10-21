"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  COACH_AUDIENCE_KEY,
  fetchJournalExports,
  JOURNAL_EXPORTS_KEY,
  requestJournalExport,
  saveCoachAudience,
  type JournalExport,
} from "@/api/journal";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine } from "@/components/community/Sheet";
import { CoachChips, markAudienceAsked, useCoachAudience } from "@/components/journal/EntryAudience";
import { coachGroups, keysOf, refOf, toggleCoach } from "@/lib/coach-audience";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

/** Ρυθμίσεις › Ημερολόγιο (ADR-162): «Οι coach μου» (with several providers) and «Εξαγωγή». */
export function JournalSettingsSections() {
  const t = useTranslations("Providers");
  const audience = useCoachAudience();
  return (
    <>
      {audience.multiple ? (
        <CollapsibleSection id="coach-audience" title={t("audience.settingTitle")} description={t("audience.settingDescription")}>
          <CoachAudienceSetting />
        </CollapsibleSection>
      ) : null}
      <CollapsibleSection id="journal-export" title={t("export.title")} description={t("export.description")}>
        <JournalExportSetting />
      </CollapsibleSection>
    </>
  );
}

/**
 * Ρυθμίσεις › «Οι coach μου» (board 17 Q5; per coach): which coaches the
 * coach rungs reach by default. Shown once there is more than one coach.
 */
export function CoachAudienceSetting() {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const audience = useCoachAudience();
  const save = useMutation({
    mutationFn: (keys: string[]) => saveCoachAudience(tokens!.access_token, keys.map(refOf)),
    onSuccess: (data) => {
      markAudienceAsked();
      queryClient.setQueriesData({ queryKey: COACH_AUDIENCE_KEY }, data);
    },
  });

  if (!audience.multiple) return null;
  if (audience.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (audience.isError) return <ErrorLine message={clientErrorMessage(audience.error, i18n)} />;

  const selected = save.variables ?? keysOf(audience.data.coaches);
  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("audience.settingHint")}</p>
      <CoachChips
        groups={coachGroups(audience.data)}
        selected={selected}
        disabled={save.isPending}
        onToggle={(key) => save.mutate(toggleCoach(selected, key))}
      />
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("audience.ownAlways")}</p>
      <ErrorLine message={save.error ? clientErrorMessage(save.error, i18n) : null} />
    </div>
  );
}

/**
 * Ρυθμίσεις › «Εξαγωγή» (board 17 Q6 extra): the whole journal, every
 * provider, prepared in the background; the list refreshes while one is
 * being prepared and offers the files once ready.
 */
export function JournalExportSetting() {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [conflict, setConflict] = useState(false);
  const exports = useQuery({
    queryKey: [...JOURNAL_EXPORTS_KEY, token],
    enabled: Boolean(token),
    queryFn: () => fetchJournalExports(token!),
    refetchInterval: (query) => (query.state.data?.some?.((item) => item.status === "pending") ? 3000 : false),
  });
  const request = useMutation({
    mutationFn: () => requestJournalExport(token!),
    onMutate: () => setConflict(false),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: JOURNAL_EXPORTS_KEY }),
    onError: (error) => {
      if (error instanceof ApiError && error.status === 409) {
        setConflict(true);
        void queryClient.invalidateQueries({ queryKey: JOURNAL_EXPORTS_KEY });
      }
    },
  });
  const pending = exports.data?.some?.((item) => item.status === "pending") ?? false;
  const when = (iso: string) => new Date(iso).toLocaleString(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("export.hint")}</p>
      <button
        type="button"
        onClick={() => request.mutate()}
        disabled={!token || pending || request.isPending}
        className="min-h-11 self-start rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--bg)" }}
      >
        {pending || request.isPending ? t("export.preparing") : t("export.request")}
      </button>
      {conflict ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("export.inProgress")}</p> : null}
      <ErrorLine message={request.error && !conflict ? clientErrorMessage(request.error, i18n) : null} />
      {Array.isArray(exports.data) && exports.data.length ? (
        <ul className="flex flex-col gap-2" aria-label={t("export.history")}>
          {exports.data.map((item) => (
            <ExportRow key={item.id} item={item} when={when} />
          ))}
        </ul>
      ) : null}
    </div>
  );
}

function ExportRow({ item, when }: { item: JournalExport; when: (iso: string) => string }) {
  const t = useTranslations("Providers");
  return (
    <li className="flex flex-col gap-1 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
        <span style={{ color: "var(--text)" }}>{when(item.requested_at)}</span>
        <span className="text-xs font-semibold" style={{ color: item.status === "failed" ? "var(--danger)" : "var(--dim)" }}>
          {t(`export.status.${item.status}`)}
          {item.status === "ready" && typeof item.entry_count === "number" ? ` · ${t("export.entries", { count: item.entry_count })}` : ""}
        </span>
      </div>
      {item.status === "ready" ? (
        <div className="flex flex-wrap gap-2">
          {item.files
            .filter((file) => file.download_url)
            .map((file) => (
              <a
                key={file.name}
                href={file.download_url!}
                download={file.name}
                className="rounded-full px-3 py-1.5 text-xs font-semibold"
                style={{ background: "var(--border)", color: "var(--text)" }}
              >
                {t("export.download", { name: file.name })}
              </a>
            ))}
        </div>
      ) : null}
      {item.status === "ready" && item.expires_at ? (
        <span className="text-xs" style={{ color: "var(--dim)" }}>{t("export.expires", { date: when(item.expires_at) })}</span>
      ) : null}
    </li>
  );
}
