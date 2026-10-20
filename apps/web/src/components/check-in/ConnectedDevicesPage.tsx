"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { regenerateCalendarExportLinks } from "@/api/calendar";
import { CONNECTED_DEVICES_KEY, fetchConnectedDevices, revokeWalletPass, type ConnectedDevices, type Integration, type WalletPass } from "@/api/check-in";
import { useSession } from "@/components/session-provider";

import { ConfirmButton } from "./ConfirmButton";
import { checkInErrorKey } from "./errors";

/**
 * Εγώ › Συνδεδεμένες συσκευές (ADR-155 §11, vision §7.11): the Wallet cards
 * at every box (revoking one resets that box's code), the calendar feed to
 * subscribe to, and the health integrations as they really are: Garmin is
 * not available yet, Apple Health and Health Connect need the phone app.
 */
export function ConnectedDevicesPage() {
  const t = useTranslations("CheckIn");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const devices = useQuery({ queryKey: CONNECTED_DEVICES_KEY, enabled: Boolean(token), queryFn: () => fetchConnectedDevices(token) });

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("devicesTitle")}</h1>
      {devices.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {devices.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(checkInErrorKey(devices.error))}</p> : null}
      {devices.data ? (
        <>
          <WalletSection token={token} wallet={devices.data.wallet} />
          <CalendarSection token={token} calendar={devices.data.calendar} />
          <IntegrationsSection integrations={devices.data.integrations} />
        </>
      ) : null}
    </main>
  );
}

function Card({ title, hint, children, testId }: { title: string; hint?: string; children: React.ReactNode; testId?: string }) {
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={testId}>
      <div>
        <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{title}</h2>
        {hint ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{hint}</p> : null}
      </div>
      {children}
    </section>
  );
}

function WalletSection({ token, wallet }: { token: string; wallet: ConnectedDevices["wallet"] }) {
  const t = useTranslations("CheckIn");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [message, setMessage] = useState<string | null>(null);
  const revoke = useMutation({
    mutationFn: (id: string) => revokeWalletPass(token, id),
    onSuccess: (pass) => {
      queryClient.setQueryData<ConnectedDevices>(CONNECTED_DEVICES_KEY, (current) =>
        current ? { ...current, wallet: { ...current.wallet, passes: current.wallet.passes.map((entry) => (entry.id === pass.id ? pass : entry)) } } : current,
      );
      // The box's code was reset with the card.
      void queryClient.invalidateQueries({ queryKey: ["check-in", "my-code"] });
      setMessage(t("walletRevoked", { box: pass.box?.name ?? "" }));
    },
    onError: (error) => setMessage(t(checkInErrorKey(error))),
  });
  const active = wallet.passes.filter((pass) => pass.active);
  const available = Boolean(wallet.platforms.apple || wallet.platforms.google);
  const date = (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(new Date(iso));

  return (
    <Card title={t("walletCardsTitle")} hint={t("walletCardsHint")} testId="devices-wallet">
      {active.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{available ? t("walletNone") : t("walletUnavailable")}</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {active.map((pass: WalletPass) => (
            <li key={pass.id} className="flex flex-col gap-2 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
              <div className="flex items-center justify-between gap-3">
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{pass.box?.name ?? ""}</span>
                  <span className="text-xs" style={{ color: "var(--text-soft)" }}>
                    {t(["walletPlatform", pass.platform].join("_"))} · {t("walletAddedOn", { date: date(pass.added_at) })}
                  </span>
                </span>
                <span className="shrink-0 rounded-full px-2 py-0.5 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}>
                  {t("walletActive")}
                </span>
              </div>
              <ConfirmButton
                label={t("walletRevoke")}
                question={t("walletRevokeConfirm", { box: pass.box?.name ?? "" })}
                confirmLabel={t("walletRevokeAction")}
                pending={revoke.isPending && revoke.variables === pass.id}
                onConfirm={() => revoke.mutate(pass.id)}
                testId={["revoke", pass.id].join("-")}
              />
            </li>
          ))}
        </ul>
      )}
      {message ? <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>{message}</p> : null}
    </Card>
  );
}

function CalendarSection({ token, calendar }: { token: string; calendar: ConnectedDevices["calendar"] }) {
  const t = useTranslations("CheckIn");
  const queryClient = useQueryClient();
  const [copied, setCopied] = useState(false);
  const [manualCopy, setManualCopy] = useState(false);
  const regenerate = useMutation({
    mutationFn: () => regenerateCalendarExportLinks(token),
    onSuccess: (links) => {
      queryClient.setQueryData<ConnectedDevices>(CONNECTED_DEVICES_KEY, (current) =>
        current ? { ...current, calendar: { ...current.calendar, https_url: links.https_url, webcal_url: links.webcal_url, download_url: links.download_url } } : current,
      );
      setCopied(false);
    },
  });

  async function copy() {
    try {
      await navigator.clipboard.writeText(calendar.https_url);
      setCopied(true);
      setManualCopy(false);
      window.setTimeout(() => setCopied(false), 1_600);
    } catch {
      // No clipboard (an insecure origin, a denied permission): show the link to copy by hand.
      setManualCopy(true);
    }
  }

  return (
    <Card title={t("calendarTitle")} hint={t("calendarHint")} testId="devices-calendar">
      <div className="flex flex-wrap gap-2">
        <a href={calendar.webcal_url} className="flex min-h-11 items-center rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--text)", color: "var(--bg)" }}>
          {t("calendarSubscribe")}
        </a>
        <button type="button" onClick={() => void copy()} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {copied ? t("copied") : t("calendarCopy")}
        </button>
        {calendar.download_url ? (
          <a href={calendar.download_url} className="flex min-h-11 items-center rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("calendarDownload")}
          </a>
        ) : null}
      </div>
      {manualCopy ? (
        <label className="flex flex-col gap-1 text-xs" style={{ color: "var(--text-soft)" }}>
          {t("calendarCopyManual")}
          <input readOnly value={calendar.https_url} onFocus={(event) => event.target.select()} className="min-h-11 rounded-xl px-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }} />
        </label>
      ) : null}
      <ConfirmButton
        label={t("calendarRegenerate")}
        question={t("calendarRegenerateConfirm")}
        confirmLabel={t("calendarRegenerateAction")}
        pending={regenerate.isPending}
        onConfirm={() => regenerate.mutate()}
      />
      {regenerate.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(checkInErrorKey(regenerate.error))}</p> : null}
    </Card>
  );
}

function IntegrationsSection({ integrations }: { integrations: Integration[] }) {
  const t = useTranslations("CheckIn");
  const tone: Record<Integration["status"], { color: string; background: string }> = {
    connected: { color: "var(--success)", background: "color-mix(in srgb, var(--success) 16%, transparent)" },
    disconnected: { color: "var(--text-soft)", background: "var(--panel-raised)" },
    unavailable: { color: "var(--dim)", background: "var(--panel-raised)" },
    native_only: { color: "var(--text-soft)", background: "var(--panel-raised)" },
  };
  return (
    <Card title={t("integrationsTitle")} hint={t("integrationsHint")} testId="devices-integrations">
      <ul className="flex flex-col gap-2">
        {integrations.map((integration) => (
          <li key={integration.provider} className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
            <span className="flex min-w-0 flex-col">
              <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(["provider", integration.provider].join("_"))}</span>
              <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t(["integrationHint", integration.status].join("_"))}</span>
            </span>
            <span className="shrink-0 rounded-full px-3 py-1 text-xs font-bold" style={tone[integration.status]}>
              {t(["integrationStatus", integration.status].join("_"))}
            </span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
