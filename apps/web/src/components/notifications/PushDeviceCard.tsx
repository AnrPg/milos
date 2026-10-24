"use client";

import { useState } from "react";
import { useUiTranslations } from "@/i18n/ui";

import type { usePushNotifications } from "@/hooks/usePushNotifications";

export type PushControl = ReturnType<typeof usePushNotifications>;

/**
 * Push on this device: its state, and the button that asks the browser or
 * the store app for permission (or turns it off). One card for the bell,
 * which offers it while push is off, and Ρυθμίσεις › Ειδοποιήσεις (ADR-199).
 */
export function PushDeviceCard({ push, isAdmin, className }: { push: PushControl; isAdmin: boolean; className?: string }) {
  const i18n = useUiTranslations();
  const [helpOpen, setHelpOpen] = useState(false);

  const statusMessage = (() => {
    if (push.error) return push.error;
    if (push.configured === false) return i18n("browserPushIsNotConfiguredOnTheServerbf1bd61");
    if (push.permission === "denied" || push.state === "blocked") {
      return i18n("browserPushIsBlockedInYourBrowserSettings0301fc4");
    }

    switch (push.step) {
      case "fetch-config":
        return i18n("checkingPushConfiguration4733bdc");
      case "register-worker":
        return i18n("registeringTheBrowserServiceWorker6ef3f3d");
      case "browser-subscription":
        return push.state === "enabling"
          ? i18n("creatingABrowserPushSubscription1bac6ad")
          : i18n("enableBrowserPushForApprovalsNotesAndAlerts4f4ec8d");
      case "server-save":
        return i18n("savingThisBrowserSubscriptionToTheServerd3589ad");
      case "server-verify":
        return i18n("verifyingThatTheServerPersistedThisBrowserSubscriptiona0178c5");
      default:
        return i18n("enableBrowserPushForApprovalsNotesAndAlerts4f4ec8d");
    }
  })();
  const statusTone = push.error || push.configured === false ? "var(--primary)" : "var(--muted)";
  const enableLabel = push.busy
    ? push.step === "server-save"
      ? i18n("savingae7e887")
      : i18n("enabling2b8e03e")
    : i18n("enable20063ad");

  return (
    <div
      data-testid="push-device-card"
      className={className ?? "rounded-[1.2rem] p-4"}
      style={{ border: "1px solid var(--border)", background: "var(--panel-muted)" }}
    >
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: push.enabled && !push.error ? "var(--success)" : statusTone }}>
            {push.enabled && !push.error ? i18n("browserPushIsOnForThisDevicea620272") : statusMessage}
          </p>
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
            {i18n("thisChoiceAppliesOnlyToThisBrowserAnd0ca4181")}
          </p>
        </div>
        {push.enabled ? (
          <button
            className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
            disabled={push.busy}
            onClick={() => void push.disablePush()}
            type="button"
          >
            {push.busy ? i18n("disabling3bf14ec") : i18n("disable9a7d4e0")}
          </button>
        ) : push.permission !== "denied" && push.configured !== false ? (
          <button
            className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={push.busy}
            onClick={() => void push.enablePush()}
            type="button"
          >
            {enableLabel}
          </button>
        ) : (
          <button
            className="shrink-0 rounded-full px-4 py-2 text-xs font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
            onClick={() => setHelpOpen((current) => !current)}
            type="button"
          >
            {isAdmin ? i18n("setupcdd7bb2") : i18n("whatNowe1cd551")}
          </button>
        )}
      </div>
      {helpOpen && push.configured === false ? (
        <div className="mt-3 rounded-xl p-3 text-xs leading-5" style={{ background: "var(--panel)", color: "var(--muted)" }}>
          {isAdmin ? i18n("generateAVapidKeyPairSetWebPushdabd06b") : i18n("theGymServerHasNotEnabledBrowserPushe7cec31")}
        </div>
      ) : helpOpen && push.permission === "denied" ? (
        <div className="mt-3 rounded-xl p-3 text-xs leading-5" style={{ background: "var(--panel)", color: "var(--muted)" }}>
          {i18n("openThisSiteSPermissionsInYourBrowserdb34d1a")}
        </div>
      ) : null}
    </div>
  );
}
