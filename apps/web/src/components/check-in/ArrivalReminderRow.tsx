"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { GEOFENCE_SYNC_EVENT } from "@/components/platform/WidgetsGeofenceBridge";
import { usePlatform } from "@/hooks/usePlatform";
import { geofencePlugin, reminderEnabled, setReminderEnabled } from "@/lib/platform/geofence";

type Hint = "background" | "denied" | null;

/**
 * Box › Check-in, inside the store app only (ADR-173): «Υπενθύμιση όταν
 * φτάνω». When on, the phone reminds the member as they arrive at a box
 * location with a booking whose check-in window is open; a tap checks them
 * in. The choice stays on this phone, off by default; the location never
 * leaves it.
 */
export function ArrivalReminderRow() {
  const { capabilities } = usePlatform();
  if (!capabilities.geofence) return null;
  return <Row />;
}

function Row() {
  const t = useTranslations("NativeExtras");
  const [on, setOn] = useState(reminderEnabled);
  const [hint, setHint] = useState<Hint>(null);
  const [pending, setPending] = useState(false);

  async function change(next: boolean) {
    setPending(true);
    setHint(null);
    try {
      if (next) {
        const plugin = await geofencePlugin();
        const permissions = await plugin.requestPermissions();
        if (permissions.location === "denied") {
          setHint("denied");
          return;
        }
        if (permissions.location === "when_in_use") setHint("background");
      }
      setReminderEnabled(next);
      setOn(next);
      window.dispatchEvent(new Event(GEOFENCE_SYNC_EVENT));
    } catch {
      setHint("denied");
    } finally {
      setPending(false);
    }
  }

  return (
    <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="arrival-reminder">
      <label className="flex items-start justify-between gap-4">
        <span className="flex flex-col">
          <span className="text-base font-bold" style={{ color: "var(--text)" }}>{t("reminderToggle")}</span>
          <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("reminderToggleHint")}</span>
        </span>
        <input
          type="checkbox"
          role="switch"
          className="mt-1 h-5 w-5 shrink-0"
          checked={on}
          disabled={pending}
          onChange={(event) => void change(event.target.checked)}
        />
      </label>
      {hint ? (
        <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t(hint === "denied" ? "reminderDenied" : "reminderNeedsAlways")}
        </p>
      ) : null}
    </section>
  );
}
