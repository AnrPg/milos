"use client";

import { useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  BODY_CONSENTS_KEY,
  BODY_KEY,
  deleteAllBodyPhotos,
  fetchBodyAccessLog,
  grantHealthConsent,
  withdrawHealthConsent,
  type BodySettingsUpdate,
} from "@/api/body";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { ChoicePill, ErrorLine } from "@/components/community/Sheet";
import { Card, Eyebrow, PillButton, dateFormat, key } from "@/components/body/BodyBits";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { bodyErrorMessage } from "@/components/body/errors";
import { useBodySettings, useBodyToken, useHealthConsents, useUpdateBodySettings } from "@/components/body/use-body";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { BackLink } from "@/components/ui/BackLink";

const REMINDERS: (number | null)[] = [null, 2, 4];

/**
 * Σώμα › Ρυθμίσεις (ADR-158 §7, board 13): the measurement reminder, blur,
 * the body-photo consent with withdrawal, who of your coaches looked and
 * when, and deleting every photo after an in-page confirmation. Units and
 * journal sections live in Εγώ › Ρυθμίσεις, who sees a new measurement in
 * Κοινοποίηση & ορατότητα (ADR-196: one home each).
 */
export function BodySettingsPage() {
  const t = useTranslations("Body");
  const tMe = useTranslations("MemberApp");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const token = useBodyToken();
  const queryClient = useQueryClient();
  const settings = useBodySettings();
  const update = useUpdateBodySettings();
  const consents = useHealthConsents();
  const accessLog = useQuery({
    queryKey: [...BODY_KEY, "access-log"],
    enabled: Boolean(token),
    queryFn: () => fetchBodyAccessLog(token!),
  });
  const consentMutation = useMutation({
    mutationFn: (grant: boolean) => (grant ? grantHealthConsent(token!, "body_photos") : withdrawHealthConsent(token!, "body_photos")),
    onSuccess: (next) => queryClient.setQueryData(BODY_CONSENTS_KEY, next),
  });
  const [confirmDelete, setConfirmDelete] = useState(false);
  const deleteAll = useMutation({
    mutationFn: () => deleteAllBodyPhotos(token!),
    onSuccess: () => {
      setConfirmDelete(false);
      void queryClient.invalidateQueries({ queryKey: BODY_KEY });
      void queryClient.invalidateQueries({ queryKey: ["my", "journal"] });
    },
  });

  if (settings.isPending) return <LoadingLine />;
  if (settings.isError) return <QueryProblem error={settings.error} onRetry={() => void settings.refetch()} />;

  const prefs = settings.data.settings;
  const save = (change: BodySettingsUpdate) => update.mutate(change);
  const consent = consents.data?.find((item) => item.scope === "body_photos");
  const dates = dateFormat(locale);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <BackLink href="/journal/body" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("title")}</BackLink>
        <h1 className="mt-1 text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("settingsTitle")}</h1>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("settingsIntro")}</p>
        <p className="mt-2 flex flex-wrap gap-x-4 text-sm font-semibold">
          <Link href="/me/settings#units" style={{ color: "var(--primary)" }}>{t("unitsAndSectionsLink")} ›</Link>
          <Link href="/me/sharing#defaults" style={{ color: "var(--primary)" }}>{tMe("meSharing")} ›</Link>
        </p>
      </div>

      <Card label={t("reminderLabel")}>
        <Eyebrow>{t("reminderLabel")}</Eyebrow>
        <div role="radiogroup" aria-label={t("reminderLabel")} className="flex flex-wrap gap-2">
          {REMINDERS.map((weeks) => (
            <ChoicePill key={String(weeks)} selected={prefs.measure_reminder_weeks === weeks} onSelect={() => save({ measure_reminder_weeks: weeks })}>
              {weeks === null ? t("reminderOff") : t("reminderEvery", { weeks })}
            </ChoicePill>
          ))}
        </div>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("reminderHint")}</p>
      </Card>

      <Card label={t("photosLabel")}>
        <Eyebrow>{t("photosLabel")}</Eyebrow>
        <Switch label={t("blurLabel")} hint={t("blurHint")} checked={prefs.blur_photos} onChange={(next) => save({ blur_photos: next })} />
        <div className="flex flex-col gap-1 border-t pt-3" style={{ borderColor: "var(--border)" }}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("consentStatusLabel")}</p>
          <p className="text-sm" style={{ color: "var(--muted)" }} data-testid="consent-status">
            {consent?.active
              ? t("consentActive", { date: consent.granted_at ? dates.dayYear(consent.granted_at) : "" })
              : consent?.withdrawn_at
                ? t("consentWithdrawn", { date: dates.dayYear(consent.withdrawn_at) })
                : t("consentNone")}
          </p>
          {consent?.active ? (
            <>
              <p className="text-xs" style={{ color: "var(--dim)" }}>{t("withdrawHint")}</p>
              <div>
                <PillButton disabled={consentMutation.isPending} onClick={() => consentMutation.mutate(false)}>{t("withdraw")}</PillButton>
              </div>
            </>
          ) : consent?.withdrawn_at ? (
            <div>
              <PillButton disabled={consentMutation.isPending} onClick={() => consentMutation.mutate(true)}>{t("consentAgree")}</PillButton>
            </div>
          ) : null}
          <ErrorLine message={consentMutation.error ? bodyErrorMessage(consentMutation.error, t, tUi) : null} />
        </div>
        <div className="flex flex-col gap-2 border-t pt-3" style={{ borderColor: "var(--border)" }}>
          {confirmDelete ? (
            <div className="flex flex-col gap-2" role="group" aria-label={t("deleteAllTitle")}>
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("deleteAllTitle")}</p>
              <p className="text-sm" style={{ color: "var(--muted)" }}>{t("deleteAllBody")}</p>
              <div className="flex gap-2">
                <PillButton onClick={() => setConfirmDelete(false)}>{t("cancel")}</PillButton>
                <PillButton danger disabled={deleteAll.isPending} onClick={() => deleteAll.mutate()}>{t("deleteAllConfirm")}</PillButton>
              </div>
            </div>
          ) : (
            <div>
              <PillButton danger onClick={() => setConfirmDelete(true)}>{t("deleteAll")}</PillButton>
            </div>
          )}
          {deleteAll.data ? (
            <p role="status" className="text-sm" style={{ color: "var(--muted)" }}>
              {t("deleteAllDone", { count: deleteAll.data.deleted_photos })}
            </p>
          ) : null}
          <ErrorLine message={deleteAll.error ? bodyErrorMessage(deleteAll.error, t, tUi) : null} />
        </div>
      </Card>

      <Card label={t("accessLogLabel")}>
        <Eyebrow>{t("accessLogLabel")}</Eyebrow>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("accessLogHint")}</p>
        {accessLog.isPending ? (
          <LoadingLine />
        ) : accessLog.isError ? (
          <QueryProblem error={accessLog.error} onRetry={() => void accessLog.refetch()} />
        ) : accessLog.data.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("accessLogEmpty")}</p>
        ) : (
          <ul className="flex flex-col gap-2" data-testid="access-log">
            {accessLog.data.map((entry) => (
              <li key={entry.id} className="text-sm" style={{ color: "var(--text)" }}>
                {t(key("accessLogEntry", entry.subject), {
                  coach: entry.reader.nickname ?? t("aCoach"),
                  date: dates.day(entry.read_at),
                  count: entry.snapshot_ids.length,
                })}
                {entry.photos_shown ? <span style={{ color: "var(--dim)" }}> · {t("accessLogPhotos")}</span> : null}
                {entry.organization?.name ? <span style={{ color: "var(--dim)" }}> · {entry.organization.name}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </Card>
      <ErrorLine message={update.error ? bodyErrorMessage(update.error, t, tUi) : null} />
    </div>
  );
}
