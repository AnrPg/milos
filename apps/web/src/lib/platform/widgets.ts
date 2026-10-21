"use client";

// ADR-173: home-screen widgets inside the store apps («+1 νερό», Σήμερα,
// Check-in), through the app's own `MilosWidgets` plugin (WidgetKit on iOS,
// App Widgets on Android). Widgets run outside the web view, so the app hands
// them a widget token of their own (POST /api/me/widget-tokens), the host to
// call and the words to show; the native side fetches /api/widget/snapshot.
// In a browser nothing here runs and nothing is downloaded.
import { issueWidgetToken, revokeWidgetToken } from "@/api/widgets";

import { hasCapability, nativePlatform } from "./index";

/** The words the widgets show, in the person's language. */
export type WidgetLabels = {
  water: string;
  addGlass: string;
  today: string;
  nothingToday: string;
  checkIn: string;
  noClass: string;
  openApp: string;
  wod: string;
  program: string;
  class: string;
  appointment: string;
};

/** Where a widget tap opens the app (paths on the app's host). */
export const WIDGET_PATHS = { water: "/journal/wellbeing", today: "/box", checkIn: "/box/check-in" } as const;

export type WidgetSession = {
  token: string;
  baseUrl: string;
  labels: WidgetLabels;
  paths: typeof WIDGET_PATHS;
};

export type MilosWidgetsPlugin = {
  setSession(session: WidgetSession): Promise<void>;
  clear(): Promise<void>;
};

type StoredToken = { id: string; token: string; userId: string; issuedAt: string };

const STORAGE_KEY = "milos-widget-token";
// The token lives 180 days; the app renews it well before.
export const RENEW_AFTER_DAYS = 30;

export function widgetsSupported() {
  return hasCapability("widgets");
}

let pluginPromise: Promise<MilosWidgetsPlugin> | null = null;

// Capacitor's plugin proxy answers `then`, so it travels wrapped (see health.ts).
export function widgetsPlugin(): Promise<MilosWidgetsPlugin> {
  pluginPromise ??= import("@capacitor/core").then(({ registerPlugin }) => {
    const native = registerPlugin<MilosWidgetsPlugin>("MilosWidgets");
    return { setSession: (session) => native.setSession(session), clear: () => native.clear() };
  });
  return pluginPromise;
}

function readStored(): StoredToken | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    const value = raw ? (JSON.parse(raw) as StoredToken) : null;
    return value && typeof value.id === "string" && typeof value.token === "string" ? value : null;
  } catch {
    return null;
  }
}

function writeStored(value: StoredToken | null) {
  try {
    if (value) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
    else window.localStorage.removeItem(STORAGE_KEY);
  } catch {}
}

/** Whether this install needs a new widget token (none, another person's, or getting old). */
export function renewalDue(stored: StoredToken | null, userId: string, now: Date = new Date()): boolean {
  if (!stored || stored.userId !== userId) return true;
  const issued = Date.parse(stored.issuedAt);
  return Number.isNaN(issued) || now.getTime() - issued >= RENEW_AFTER_DAYS * 86_400_000;
}

let inflight: Promise<void> | null = null;

/**
 * Gives the widgets a valid token, the host and today's words. Runs when the
 * app opens and each time the person comes back; one at a time.
 */
export function syncWidgets(
  accessToken: string,
  userId: string,
  labels: WidgetLabels,
  options: { plugin?: MilosWidgetsPlugin; origin?: string; now?: Date } = {},
): Promise<void> {
  inflight ??= (async () => {
    const platform = nativePlatform();
    if (!platform) return;
    let stored = readStored();
    if (renewalDue(stored, userId, options.now)) {
      const issued = await issueWidgetToken(accessToken, platform, stored?.userId === userId ? stored.id : null);
      stored = { id: issued.id, token: issued.token, userId, issuedAt: (options.now ?? new Date()).toISOString() };
      writeStored(stored);
    }
    const plugin = options.plugin ?? (await widgetsPlugin());
    await plugin.setSession({ token: stored!.token, baseUrl: options.origin ?? window.location.origin, labels, paths: WIDGET_PATHS });
  })().finally(() => {
    inflight = null;
  });
  return inflight;
}

/** Sign-out: the widgets go blank and their token stops working. */
export async function forgetWidgets(accessToken?: string | null, plugin?: MilosWidgetsPlugin): Promise<void> {
  if (!widgetsSupported() && !plugin) return;
  const stored = readStored();
  writeStored(null);
  try {
    await (plugin ?? (await widgetsPlugin())).clear();
  } catch {}
  if (stored && accessToken) {
    try {
      await revokeWidgetToken(accessToken, stored.id);
    } catch {
      // The token still dies with its age; the widget shows «open the app».
    }
  }
}
