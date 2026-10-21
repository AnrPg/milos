"use client";

// ADR-173: inside the store app, keeps the home-screen widgets and the
// arrival reminder current: when the app opens, each time the person comes
// back to it, and when the reminder is switched on (`GEOFENCE_SYNC_EVENT`).
// Renders nothing and does nothing in a browser or in an app build without
// these plugins. Sign-out clears both (`lib/push-subscription`).
import { useLocale, useTranslations } from "next-intl";
import { useEffect } from "react";

import { useSession } from "@/components/session-provider";
import { geofenceSupported, syncGeofences, type ReminderWords } from "@/lib/platform/geofence";
import { syncWidgets, widgetsSupported, type WidgetLabels } from "@/lib/platform/widgets";

type Removable = { remove: () => Promise<void> };

/** Fired by Box › Check-in after the member turns the reminder on or off. */
export const GEOFENCE_SYNC_EVENT = "palee:geofence-sync";

type Translate = ReturnType<typeof useTranslations<"NativeExtras">>;

/** The widgets' and the reminder's words in the person's language. */
function words(t: Translate, locale: string): { labels: WidgetLabels; reminder: ReminderWords; time: (iso: string) => string } {
  return {
    labels: {
      water: t("widgetWater"),
      addGlass: t("widgetAddGlass"),
      today: t("widgetToday"),
      nothingToday: t("widgetNothingToday"),
      checkIn: t("widgetCheckIn"),
      noClass: t("widgetNoClass"),
      openApp: t("widgetOpenApp"),
      wod: t("widgetKind_wod"),
      program: t("widgetKind_program"),
      class: t("widgetKind_class"),
      appointment: t("widgetKind_appointment"),
    },
    reminder: ({ box, className, time }) => ({
      title: t("reminderTitle", { box }),
      body: className ? t("reminderBody", { className, time }) : t("reminderBodyNoName", { time }),
    }),
    time: (iso) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(iso)),
  };
}

export function WidgetsGeofenceBridge() {
  const t = useTranslations("NativeExtras");
  const locale = useLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const userId = currentUser?.id ?? null;

  useEffect(() => {
    const widgets = widgetsSupported();
    const geofence = geofenceSupported();
    if (!token || !userId || (!widgets && !geofence)) return;
    let disposed = false;
    let handle: Removable | null = null;

    const current = words(t, locale);
    // A failed sync waits for the next opening; the widget keeps its last snapshot.
    const run = () => {
      if (widgets) void syncWidgets(token, userId, current.labels).catch(() => undefined);
      if (geofence) void syncGeofences(token, current.reminder, current.time).catch(() => undefined);
    };

    run();
    window.addEventListener(GEOFENCE_SYNC_EVENT, run);
    void (async () => {
      const { App } = await import("@capacitor/app");
      const listener = await App.addListener("resume", run);
      if (disposed) void listener.remove();
      else handle = listener;
    })().catch(() => undefined);

    return () => {
      disposed = true;
      window.removeEventListener(GEOFENCE_SYNC_EVENT, run);
      void handle?.remove();
    };
  }, [token, userId, locale, t]);

  return null;
}
