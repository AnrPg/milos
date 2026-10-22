"use client";

import { type CSSProperties, useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { regenerateCalendarExportLinks } from "@/api/calendar";
import { revokeWalletPass, type ConnectedDevices, type Integration, type WalletPass } from "@/api/check-in";
import { DEVICES_KEY as CONNECTED_DEVICES_KEY, fetchDevices } from "@/api/devices";
import { GarminRowItem } from "@/components/devices/GarminRow";
import { garminReturn, garminRowOf, returnReasonKey } from "@/components/devices/garmin-model";
import { DeviceDataExport } from "@/components/devices/DeviceDataExport";
import { PhoneHealthRowItem } from "@/components/devices/PhoneHealthRow";
import { anyDeviceConnected, isPhoneProvider, phoneRowOf, showsPhoneRow } from "@/components/devices/phone-health-model";
import { useSession } from "@/components/session-provider";
import { usePlatform } from "@/hooks/usePlatform";
import { integrationStatusKey, visibleIntegrations } from "@/lib/platform/device-rows";

import { ConfirmButton } from "./ConfirmButton";
import { checkInErrorKey } from "./errors";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

/**
 * Εγώ › Συνδεδεμένες συσκευές (ADR-155 §11, vision §7.11): the Wallet cards
 * at every box (revoking one resets that box's code), the calendar feed to
 * subscribe to, and the health integrations as they really are: Garmin
 * (ADR-161) connects here, Apple Health and Health Connect connect from the
 * phone app (ADR-172).
 */
export function ConnectedDevicesPage() {
  const t = useTranslations("CheckIn");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const devices = useQuery({ queryKey: CONNECTED_DEVICES_KEY, enabled: Boolean(token), queryFn: () => fetchDevices(token) });
  const toast = useGarminReturnToast();

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("devicesTitle")}</h1>
      {toast.message ? (
        <div
          role="status"
          data-testid="garmin-return"
          className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3 text-sm"
          style={{
            background: toast.ok ? "color-mix(in srgb, var(--success) 14%, var(--panel))" : "color-mix(in srgb, var(--danger) 12%, var(--panel))",
            border: `1px solid ${toast.ok ? "var(--success)" : "var(--danger)"}`,
            color: "var(--text)",
          }}
        >
          <span>{toast.message}</span>
          <button type="button" onClick={toast.dismiss} className="shrink-0 font-bold" style={{ color: "var(--primary)" }}>
            {toast.dismissLabel}
          </button>
        </div>
      ) : null}
      {devices.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {devices.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(checkInErrorKey(devices.error))}</p> : null}
      {devices.data ? (
        <>
          <WalletSection token={token} wallet={devices.data.wallet} />
          <CalendarSection token={token} calendar={devices.data.calendar} />
          <IntegrationsSection token={token} integrations={devices.data.integrations} />
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
                <span className="shrink-0 rounded-full px-2 py-0.5 text-xs font-bold" style={SPARK_ACTIVE_STYLE}>
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

/**
 * The OAuth return (`?garmin=connected|error&reason=…`, ADR-161): one toast,
 * then the query leaves the address so a reload does not repeat it.
 */
function useGarminReturnToast() {
  const t = useTranslations("Devices");
  const [outcome, setOutcome] = useState<ReturnType<typeof garminReturn>>(null);
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const found = garminReturn(params);
    if (!found) return;
    // Read once from the address on mount; the address is then cleaned.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setOutcome(found);
    params.delete("garmin");
    params.delete("reason");
    const query = params.toString();
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${query ? `?${query}` : ""}`);
  }, []);
  const message = !outcome
    ? null
    : outcome.outcome === "connected"
      ? t("returnConnected")
      : t(["return", returnReasonKey(outcome.reason)].join("_"));
  return { message, ok: outcome?.outcome === "connected", dismiss: () => setOutcome(null), dismissLabel: t("dismiss") };
}

function IntegrationsSection({ token, integrations }: { token: string; integrations: Integration[] }) {
  const t = useTranslations("CheckIn");
  const [message, setMessage] = useState<string | null>(null);
  const garmin = garminRowOf(integrations);
  const { platform, capabilities } = usePlatform();
  // This app install's phone-health provider, when its plugin ships (ADR-172).
  const appProvider =
    platform === "ios" && capabilities.healthKit ? "apple_health" : platform === "android" && capabilities.healthConnect ? "health_connect" : null;
  const tone: Record<string, { color?: CSSProperties["color"]; background?: CSSProperties["background"] }> = {
    connected: SPARK_ACTIVE_STYLE,
    disconnected: { color: "var(--text-soft)", background: "var(--panel-raised)" },
    unavailable: { color: "var(--dim)", background: "var(--panel-raised)" },
    native_only: { color: "var(--text-soft)", background: "var(--panel-raised)" },
    native_soon: { color: "var(--dim)", background: "var(--panel-raised)" },
    error: { color: "var(--danger)", background: "color-mix(in srgb, var(--danger) 16%, transparent)" },
  };
  return (
    <Card title={t("integrationsTitle")} hint={t("integrationsHint")} testId="devices-integrations">
      <ul className="flex flex-col gap-2">
        {visibleIntegrations(integrations, platform).map((integration) => {
          if (integration.provider === "garmin" && garmin) {
            return <GarminRowItem key="garmin" row={garmin} token={token} onMessage={setMessage} />;
          }
          const phoneRow = isPhoneProvider(integration.provider) && showsPhoneRow(integration, appProvider) ? phoneRowOf(integrations, integration.provider) : null;
          if (phoneRow) {
            return <PhoneHealthRowItem key={phoneRow.provider} row={phoneRow} token={token} inApp={phoneRow.provider === appProvider} onMessage={setMessage} />;
          }
          const status = integrationStatusKey(integration, platform, capabilities);
          return (
          <li key={integration.provider} className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
            <span className="flex min-w-0 flex-col">
              <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(["provider", integration.provider].join("_"))}</span>
              <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t(["integrationHint", status].join("_"))}</span>
            </span>
            <span className="shrink-0 rounded-full px-3 py-1 text-xs font-bold" style={tone[status]}>
              {t(["integrationStatus", status].join("_"))}
            </span>
          </li>
          );
        })}
      </ul>
      {message ? <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>{message}</p> : null}
      {anyDeviceConnected(integrations) ? <DeviceDataExport token={token} /> : null}
    </Card>
  );
}
