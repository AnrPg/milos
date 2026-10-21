"use client";

// ADR-173: the arrival reminder inside the store apps, through the app's own
// `PaleeGeofence` plugin (Core Location on iOS, Play Services geofencing on
// Android). The member turns it on in Box › Check-in; the app then hands the
// phone the regions from GET /api/me/check-in/geofences, each with its
// check-in windows and the reminder's words. The phone alone decides when
// the member arrives: their location never leaves it. Tapping the reminder
// opens /c/<location>/g/<token>, which checks in to the booking.
import type { Geofences, GeofenceRegion } from "@/api/check-in";
import { fetchGeofences } from "@/api/check-in";

import { hasCapability } from "./index";

export type GeofencePermission = "granted" | "when_in_use" | "denied" | "prompt";
export type GeofencePermissions = { location: GeofencePermission; notifications: "granted" | "denied" | "prompt" };

export type NativeGeofenceWindow = { from: number; to: number; title: string; body: string };

export type NativeGeofenceRegion = {
  id: string;
  latitude: number;
  longitude: number;
  radius: number;
  url: string;
  windows: NativeGeofenceWindow[];
};

export type PaleeGeofencePlugin = {
  checkPermissions(): Promise<GeofencePermissions>;
  requestPermissions(): Promise<GeofencePermissions>;
  setRegions(options: { regions: NativeGeofenceRegion[] }): Promise<{ monitored: number }>;
  clear(): Promise<void>;
};

/** How a window reads in the reminder: the box, the class and its time. */
export type ReminderWords = (window: { box: string; className: string; time: string }) => { title: string; body: string };

const PREFERENCE_KEY = "palee-geofence-reminder";

export function geofenceSupported() {
  return hasCapability("geofence");
}

let pluginPromise: Promise<PaleeGeofencePlugin> | null = null;

export function geofencePlugin(): Promise<PaleeGeofencePlugin> {
  pluginPromise ??= import("@capacitor/core").then(({ registerPlugin }) => {
    const native = registerPlugin<PaleeGeofencePlugin>("PaleeGeofence");
    return {
      checkPermissions: () => native.checkPermissions(),
      requestPermissions: () => native.requestPermissions(),
      setRegions: (options) => native.setRegions(options),
      clear: () => native.clear(),
    };
  });
  return pluginPromise;
}

/** The member's choice on this phone (off until they turn it on). */
export function reminderEnabled(): boolean {
  try {
    return window.localStorage.getItem(PREFERENCE_KEY) === "on";
  } catch {
    return false;
  }
}

export function setReminderEnabled(on: boolean) {
  try {
    if (on) window.localStorage.setItem(PREFERENCE_KEY, "on");
    else window.localStorage.removeItem(PREFERENCE_KEY);
  } catch {}
}

/** The server's regions as the phone watches them. */
export function toNativeRegions(
  regions: GeofenceRegion[],
  words: ReminderWords,
  formatTime: (iso: string) => string,
  origin: string,
): NativeGeofenceRegion[] {
  return regions.map((region) => ({
    id: region.id,
    latitude: region.latitude,
    longitude: region.longitude,
    radius: region.radius_m,
    url: `${origin}/c/${encodeURIComponent(region.location_id)}/g/${encodeURIComponent(region.token)}`,
    windows: region.windows.map((window) => ({
      from: Date.parse(window.opens_at),
      to: Date.parse(window.closes_at),
      ...words({ box: region.box_name, className: window.class_name ?? "", time: formatTime(window.starts_at) }),
    })),
  }));
}

/**
 * Hands the phone the current regions, or clears them when the reminder is
 * off. Runs when the app opens, on each return and when the member turns it
 * on. Returns how many regions the phone watches.
 */
export async function syncGeofences(
  accessToken: string,
  words: ReminderWords,
  formatTime: (iso: string) => string,
  options: { plugin?: PaleeGeofencePlugin; origin?: string; fetch?: (token: string) => Promise<Geofences> } = {},
): Promise<number> {
  const plugin = options.plugin ?? (await geofencePlugin());
  if (!reminderEnabled()) {
    await plugin.clear();
    return 0;
  }
  const data = await (options.fetch ?? fetchGeofences)(accessToken);
  const regions = toNativeRegions(data.regions, words, formatTime, options.origin ?? window.location.origin);
  const { monitored } = await plugin.setRegions({ regions });
  return monitored;
}

/** Sign-out: the phone stops watching. */
export async function forgetGeofences(plugin?: PaleeGeofencePlugin) {
  if (!geofenceSupported() && !plugin) return;
  // The next person on this phone chooses for themselves.
  setReminderEnabled(false);
  try {
    await (plugin ?? (await geofencePlugin())).clear();
  } catch {}
}
