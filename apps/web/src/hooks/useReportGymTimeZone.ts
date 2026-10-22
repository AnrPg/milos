"use client";

import { useEffect } from "react";

import { updateTimeZone } from "@/api/settings";
import { readStorage, writeStorage } from "@/lib/onboarding";
import { deviceTimeZone } from "@/lib/zoned-time";

export { deviceTimeZone };

/**
 * ADR-176: until an admin confirms the gym's time zone, an owner's or admin's
 * device reports its own zone as a guess, once per session and gym. The API
 * ignores the guess once the zone is confirmed.
 */
export function useReportGymTimeZone(enabled: boolean, token: string | null | undefined, slug: string | null) {
  useEffect(() => {
    if (!enabled || !token || !slug) return;
    const key = `palee:time-zone-reported:${slug}`;
    if (readStorage("session", key)) return;
    writeStorage("session", key, "1");
    void updateTimeZone(token, { timezone: deviceTimeZone(), source: "inferred" }).catch(() => undefined);
  }, [enabled, slug, token]);
}
