"use client";

import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  fetchPlatformPushSettings,
  replacePlatformPushKeys,
  updatePlatformPushContact,
  type PlatformPushStatus,
} from "@/api/settings";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { BackLink } from "@/components/ui/BackLink";
import { formatInZone } from "@/lib/zoned-time";

/**
 * ADR-218 / ADR-277: browser alerts for the whole Palee installation. The
 * server makes and keeps the key pair itself, so this page shows only whether
 * alerts work, how many devices allow them and the contact for push services.
 * Replacing the keys is the one rare action, behind «Advanced».
 */

const QUERY_KEY = ["platform", "push-settings"] as const;

const fieldStyle = { background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" };
const primary = { background: "var(--primary)", color: "var(--primary-contrast)" };
const quiet = { background: "var(--panel-muted)", color: "var(--muted)" };

export function PlatformPushSettingsPage() {
  const t = useTranslations("PlatformPush");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const [subject, setSubject] = useState("");
  const [confirming, setConfirming] = useState(false);

  const status = useQuery({
    queryKey: QUERY_KEY,
    queryFn: () => fetchPlatformPushSettings(token!),
    enabled: Boolean(token),
  });

  useEffect(() => {
    const saved = status.data?.vapid_subject ?? "";
    queueMicrotask(() => setSubject(saved));
  }, [status.data?.vapid_subject]);

  const store = (data: PlatformPushStatus) => queryClient.setQueryData(QUERY_KEY, data);

  const saveContact = useMutation({
    mutationFn: () => updatePlatformPushContact(token!, subject),
    onSuccess: store,
  });

  const rotate = useMutation({
    mutationFn: () => replacePlatformPushKeys(token!),
    onSuccess: (data) => {
      store(data);
      setConfirming(false);
    },
  });

  const forbidden = status.error instanceof ApiError && status.error.status === 403;
  const data = status.data;
  const fromServer = data?.source === "server";
  const subjectFromServer = data?.subject_source === "server";
  const dirty = Boolean(data) && subject.trim() !== (data?.vapid_subject ?? "");
  const contactInvalid =
    saveContact.error instanceof ApiError && saveContact.error.payload?.code === "invalid_push_contact";
  const when = (at: string) => formatInZone(at, null, locale, "date-time");

  return (
    <main className="mx-auto w-full max-w-3xl px-4 pb-24 pt-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {status.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {status.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}

      {data ? (
        <div className="mt-6 space-y-6">
          <section
            className="space-y-3 rounded-[1.4rem] border p-5"
            style={{ background: "var(--panel)", borderColor: "var(--border)" }}
          >
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-lg font-semibold text-[var(--text)]">{t("statusHeading")}</h2>
              <span
                data-testid="push-status"
                className="inline-flex items-center gap-2 rounded-full px-3 py-1 text-sm font-semibold"
                style={{
                  background: data.enabled
                    ? "color-mix(in srgb, var(--success) 14%, var(--panel-muted))"
                    : "var(--panel-muted)",
                  color: data.enabled ? "var(--success)" : "var(--muted)",
                }}
              >
                <span aria-hidden className="h-2 w-2 rounded-full" style={{ background: "currentColor" }} />
                {data.enabled ? t("statusOn") : t("statusOff")}
              </span>
            </div>
            <p className="text-sm leading-6 text-[var(--text-soft)]">{t("howMembersChoose")}</p>
            <p data-testid="push-stats" className="text-xs leading-5 text-[var(--text-soft)]">
              {t("deviceCount", { count: data.device_count })}
              {" · "}
              {data.last_sent_at ? t("lastSent", { when: when(data.last_sent_at) }) : t("neverSent")}
            </p>
            {fromServer ? <p className="text-xs leading-5 text-[var(--text-soft)]">{t("sourceServer")}</p> : null}
          </section>

          <div className="space-y-2">
            <label htmlFor="push-subject" className="block text-sm font-semibold text-[var(--text)]">
              {t("subjectLabel")}
            </label>
            <input
              id="push-subject"
              aria-describedby="push-subject-help"
              aria-invalid={contactInvalid || undefined}
              className="w-full rounded-2xl border px-4 py-3 text-sm disabled:opacity-70"
              disabled={subjectFromServer}
              placeholder={t("subjectPlaceholder")}
              style={{ ...fieldStyle, ...(contactInvalid ? { borderColor: "var(--danger)" } : null) }}
              value={subject}
              onChange={(e) => {
                setSubject(e.target.value);
                saveContact.reset();
              }}
            />
            {contactInvalid ? (
              <p className="text-xs leading-5" style={{ color: "var(--danger)" }}>{t("subjectInvalid")}</p>
            ) : null}
            <p id="push-subject-help" className="text-xs leading-5 text-[var(--text-soft)]">
              {subjectFromServer ? t("subjectServer") : t("subjectHelp")}
            </p>
            {subjectFromServer ? null : (
              <div className="flex flex-wrap items-center gap-3 pt-1">
                <button
                  type="button"
                  disabled={!dirty || saveContact.isPending}
                  onClick={() => saveContact.mutate()}
                  className="rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-60"
                  style={primary}
                >
                  {saveContact.isPending ? t("saving") : t("save")}
                </button>
                {saveContact.isSuccess && !dirty ? (
                  <span className="text-sm" style={{ color: "var(--success)" }}>{t("saved")}</span>
                ) : null}
              </div>
            )}
            {saveContact.isError && !contactInvalid ? <ErrorNotice>{t("saveError")}</ErrorNotice> : null}
          </div>

          {fromServer ? null : (
            <details className="rounded-[1.3rem] p-4" style={{ border: "1px solid var(--border)" }}>
              <summary className="cursor-pointer text-sm font-semibold text-[var(--muted)]">{t("advanced")}</summary>
              <div className="mt-3 space-y-3">
                <p className="text-sm leading-6 text-[var(--text-soft)]">{t("rotateHelp")}</p>
                {data.keys_created_at ? (
                  <p className="text-xs text-[var(--text-soft)]">{t("keysSince", { when: when(data.keys_created_at) })}</p>
                ) : null}
                {confirming ? (
                  <div
                    aria-live="polite"
                    data-testid="push-rotate-confirm"
                    className="space-y-3 rounded-2xl p-4 text-sm"
                    style={{ background: "color-mix(in srgb, var(--danger) 10%, var(--panel-muted))", color: "var(--danger)" }}
                  >
                    <p>{t("rotateConfirm", { count: data.device_count })}</p>
                    <div className="flex flex-wrap gap-3">
                      <button
                        type="button"
                        disabled={rotate.isPending}
                        onClick={() => rotate.mutate()}
                        className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
                        style={{ background: "var(--danger)", color: "var(--primary-contrast)" }}
                      >
                        {rotate.isPending ? t("rotating") : t("rotateConfirmButton")}
                      </button>
                      <button type="button" onClick={() => setConfirming(false)} className="rounded-full px-4 py-2 text-sm font-semibold" style={quiet}>
                        {t("cancel")}
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="flex flex-wrap items-center gap-3">
                    <button
                      type="button"
                      onClick={() => {
                        rotate.reset();
                        setConfirming(true);
                      }}
                      className="rounded-full px-4 py-2 text-sm font-semibold"
                      style={quiet}
                    >
                      {t("rotate")}
                    </button>
                    {rotate.isSuccess ? <span className="text-sm" style={{ color: "var(--success)" }}>{t("rotated")}</span> : null}
                  </div>
                )}
                {rotate.isError ? <ErrorNotice>{t("rotateError")}</ErrorNotice> : null}
              </div>
            </details>
          )}
        </div>
      ) : null}
    </main>
  );
}
