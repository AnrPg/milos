"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchMyInjuryAccessLog,
  INJURY_ACCESS_LOG_KEY,
  setMyInjurySharing,
  type InjuryAccessEntry,
  type InjuryRecord,
} from "@/api/wellbeing";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { dateFormat } from "@/components/body/BodyBits";
import { ErrorLine } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-286 (ANR's pick, 2026-10-30): each injury the member records carries
 * «Να το δει το box μου», on by default. While on, management and the
 * coaches who train them at every box they belong to see it; every read is
 * logged and listed in Εγώ › Κοινοποίηση.
 */
export function InjuryShareField({ checked, onChange }: { checked: boolean; onChange: (next: boolean) => void }) {
  const t = useTranslations("MemberApp.injury");
  return (
    <div data-testid="injury-share-field">
      <Switch label={t("shareLabel")} hint={t("shareHint")} checked={checked} onChange={onChange} />
    </div>
  );
}

/** A report the member recorded themselves (a box's own reports have no switch). */
export function isOwnReport(injury: Pick<InjuryRecord, "organization_id" | "reported_by_role">) {
  return !injury.organization_id && injury.reported_by_role === "self";
}

/** The switch on one of the member's own injuries. */
export function InjuryShareToggle({ injury }: { injury: InjuryRecord }) {
  const t = useTranslations("MemberApp.injury");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: (shared: boolean) => setMyInjurySharing(tokens!.access_token, String(injury.id), shared),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["my", "wellbeing", "injuries"] }),
  });
  if (!isOwnReport(injury)) return null;
  const shared = mutation.isPending ? Boolean(mutation.variables) : injury.shared_with_box !== false;
  return (
    <div className="mt-3 border-t pt-2" style={{ borderColor: "var(--border)" }}>
      <Switch label={t("shareLabel")} checked={shared} disabled={mutation.isPending} onChange={(next) => mutation.mutate(next)} />
      <ErrorLine message={mutation.error ? localizeError(mutation.error, tUi) : null} />
    </div>
  );
}

/** Εγώ › Κοινοποίηση: how injuries reach the boxes, and who of the staff read them. */
export function InjurySharingSetting() {
  const t = useTranslations("MemberApp.injury");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const log = useQuery({
    queryKey: INJURY_ACCESS_LOG_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchMyInjuryAccessLog(tokens!.access_token),
  });
  const dates = dateFormat(locale);

  return (
    <div id="injuries" className="space-y-2">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("sharingTitle")}</p>
      <p className="text-xs" style={{ color: "var(--muted)" }}>{t("sharingNote")}</p>
      <details className="text-sm">
        <summary className="min-h-11 cursor-pointer py-2 font-semibold" style={{ color: "var(--text)" }}>{t("accessTitle")}</summary>
        {log.data && log.data.length > 0 ? (
          <ul className="flex flex-col gap-2" data-testid="injury-access-log">
            {log.data.map((entry) => (
              <li key={entry.id} style={{ color: "var(--text)" }}>
                {accessLine(entry, t, dates.day(entry.read_at))}
                {entry.organization?.name ? <span style={{ color: "var(--dim)" }}> · {entry.organization.name}</span> : null}
              </li>
            ))}
          </ul>
        ) : (
          <p style={{ color: "var(--muted)" }}>{log.isPending ? "…" : t("accessEmpty")}</p>
        )}
      </details>
    </div>
  );
}

function accessLine(entry: InjuryAccessEntry, t: ReturnType<typeof useTranslations>, date: string) {
  const reader = entry.reader?.nickname ?? t("aStaffMember");
  switch (entry.surface) {
    case "box_list":
      return t("accessBoxList", { reader, date });
    case "safety_warning":
      return t("accessSafetyWarning", { reader, date });
    default:
      return t("accessProfile", { reader, date });
  }
}
