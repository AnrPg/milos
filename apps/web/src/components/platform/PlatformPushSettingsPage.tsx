"use client";

import { BackLink } from "@/components/ui/BackLink";
import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  fetchPlatformPushSettings,
  updatePlatformPushSettings,
  type NotificationPushSettings,
  type NotificationPushUpdate,
} from "@/api/settings";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { generateVapidKeyPair, normalizePushContact } from "@/lib/web-push-keys";

/**
 * ADR-218: browser alerts are signed with one key pair for the whole Palee
 * installation, so the keys live here, in the platform console, and never on
 * a gym's settings page. Each person still turns alerts on per device.
 */

type PushForm = { publicKey: string; privateKey: string; subject: string; clearPrivateKey: boolean };

const QUERY_KEY = ["platform", "push-settings"] as const;

function formFrom(settings: NotificationPushSettings): PushForm {
  return {
    publicKey: settings.vapid_public_key ?? "",
    privateKey: "",
    subject: settings.vapid_subject ?? "",
    clearPrivateKey: false,
  };
}

const fieldStyle = { background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" };

function Field({ id, label, help, children }: { id: string; label: string; help: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <label htmlFor={id} className="block text-sm font-semibold text-[var(--text)]">
        {label}
      </label>
      {children}
      <p id={`${id}-help`} className="text-xs leading-5 text-[var(--text-soft)]">
        {help}
      </p>
    </div>
  );
}

export function PlatformPushSettingsPage() {
  const t = useTranslations("PlatformPush");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const [form, setForm] = useState<PushForm>({ publicKey: "", privateKey: "", subject: "", clearPrivateKey: false });
  const [generateError, setGenerateError] = useState(false);
  const [generated, setGenerated] = useState(false);

  const settings = useQuery({
    queryKey: QUERY_KEY,
    queryFn: () => fetchPlatformPushSettings(token!),
    enabled: Boolean(token),
  });

  useEffect(() => {
    if (!settings.data) return;
    const next = formFrom(settings.data);
    queueMicrotask(() => setForm(next));
  }, [settings.data]);

  const save = useMutation({
    mutationFn: () => {
      const payload: NotificationPushUpdate = {
        vapid_public_key: form.publicKey.trim() || null,
        vapid_subject: normalizePushContact(form.subject),
      };
      const privateKey = form.privateKey.trim();
      if (privateKey || form.clearPrivateKey) payload.vapid_private_key = privateKey || null;
      return updatePlatformPushSettings(token!, payload);
    },
    onSuccess: (data) => {
      queryClient.setQueryData(QUERY_KEY, data);
      setForm(formFrom(data));
      setGenerated(false);
    },
  });

  const forbidden = settings.error instanceof ApiError && settings.error.status === 403;
  const server = settings.data ? formFrom(settings.data) : null;
  const dirty =
    server !== null &&
    (form.publicKey !== server.publicKey ||
      form.subject !== server.subject ||
      form.privateKey.trim() !== "" ||
      form.clearPrivateKey);
  const enabled = Boolean(settings.data?.enabled);
  const privateKeySaved = Boolean(settings.data?.vapid_private_key_configured);
  const replacingKeys = generated && Boolean(settings.data?.vapid_public_key);

  async function generate() {
    setGenerateError(false);
    try {
      const pair = await generateVapidKeyPair();
      setForm((current) => ({ ...current, publicKey: pair.publicKey, privateKey: pair.privateKey, clearPrivateKey: false }));
      setGenerated(true);
    } catch {
      setGenerateError(true);
    }
  }

  return (
    <main className="mx-auto w-full max-w-3xl px-4 pb-24 pt-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="self-start text-sm" style={{ color: "var(--text-soft)" }}>
          {t("back")}
        </BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {settings.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {settings.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}

      {settings.data ? (
        <div className="mt-6 space-y-6">
          <section className="space-y-2 text-sm leading-6 text-[var(--text-soft)]">
            <p>{t("howItWorks")}</p>
            <p>{t("howMembersChoose")}</p>
          </section>

          <div
            data-testid="push-status"
            className="rounded-[1.4rem] border p-4 text-sm"
            style={{
              background: enabled ? "color-mix(in srgb, var(--success) 10%, var(--panel-muted))" : "var(--panel-muted)",
              borderColor: "var(--border)",
              color: enabled ? "var(--success)" : "var(--muted)",
            }}
          >
            {enabled ? t("statusOn") : t("statusOff")}
          </div>

          <div className="space-y-2">
            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                onClick={() => void generate()}
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {privateKeySaved ? t("generateReplace") : t("generate")}
              </button>
              {privateKeySaved ? (
                <button
                  type="button"
                  onClick={() => {
                    setForm({ publicKey: "", privateKey: "", subject: "", clearPrivateKey: true });
                    setGenerated(false);
                  }}
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--panel-muted)", color: "var(--muted)" }}
                >
                  {t("turnOff")}
                </button>
              ) : null}
            </div>
            <p className="text-xs leading-5 text-[var(--text-soft)]">{t("generateHelp")}</p>
            {privateKeySaved ? <p className="text-xs leading-5 text-[var(--text-soft)]">{t("turnOffHelp")}</p> : null}
          </div>
          {generateError ? <ErrorNotice>{t("generateError")}</ErrorNotice> : null}
          {replacingKeys ? <ErrorNotice>{t("replaceWarning")}</ErrorNotice> : null}

          <Field id="push-subject" label={t("subjectLabel")} help={t("subjectHelp")}>
            <input
              id="push-subject"
              aria-describedby="push-subject-help"
              className="w-full rounded-2xl border px-4 py-3 text-sm"
              placeholder={t("subjectPlaceholder")}
              style={fieldStyle}
              value={form.subject}
              onChange={(e) => setForm((current) => ({ ...current, subject: e.target.value, clearPrivateKey: false }))}
            />
          </Field>

          <Field id="push-public-key" label={t("publicKeyLabel")} help={t("publicKeyHelp")}>
            <textarea
              id="push-public-key"
              aria-describedby="push-public-key-help"
              className="min-h-24 w-full rounded-2xl border px-4 py-3 font-mono text-xs"
              spellCheck={false}
              style={fieldStyle}
              value={form.publicKey}
              onChange={(e) => setForm((current) => ({ ...current, publicKey: e.target.value, clearPrivateKey: false }))}
            />
          </Field>

          <Field
            id="push-private-key"
            label={privateKeySaved ? t("privateKeyReplaceLabel") : t("privateKeyLabel")}
            help={t("privateKeyHelp")}
          >
            <textarea
              id="push-private-key"
              aria-describedby="push-private-key-help"
              className="min-h-24 w-full rounded-2xl border px-4 py-3 font-mono text-xs"
              placeholder={privateKeySaved ? t("privateKeyKeep") : ""}
              spellCheck={false}
              style={fieldStyle}
              value={form.privateKey}
              onChange={(e) => setForm((current) => ({ ...current, privateKey: e.target.value, clearPrivateKey: false }))}
            />
          </Field>

          {save.isError ? <ErrorNotice>{t("saveError")}</ErrorNotice> : null}

          <div className="flex flex-wrap items-center gap-3">
            <button
              type="button"
              disabled={!dirty || save.isPending}
              onClick={() => save.mutate()}
              className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-60"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {save.isPending ? t("saving") : t("save")}
            </button>
            {dirty ? (
              <button
                type="button"
                onClick={() => {
                  if (server) setForm(server);
                  setGenerated(false);
                }}
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--panel-muted)", color: "var(--muted)" }}
              >
                {t("reset")}
              </button>
            ) : null}
            {save.isSuccess && !dirty ? <span className="text-sm" style={{ color: "var(--success)" }}>{t("saved")}</span> : null}
          </div>
        </div>
      ) : null}
    </main>
  );
}
