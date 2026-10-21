"use client";

// ADR-172: the phone's health store inside the store apps, through the app's
// own `MilosHealth` plugin (Swift HealthKit on iOS, Kotlin Health Connect on
// Android, one interface). In a browser nothing here runs and nothing is
// downloaded: @capacitor/core is imported lazily, only inside the app.
import { ingestPhoneHealth, type PhoneHealthProvider, type PhoneHealthRow } from "@/api/phone-health";

import { toIngestBatches, type HealthKind, type RawHealthRead } from "./health-batch";
import { hasCapability, nativePlatform, type NativePlatform } from "./index";

export type HealthAvailability = { available: boolean; reason?: "unsupported" | "not_installed" | "update_required" | null };

/** `granted` is null on iOS: HealthKit never tells an app what it may read. */
export type HealthAuthorization = { asked: HealthKind[]; granted: HealthKind[] | null };

export type MilosHealthPlugin = {
  availability(): Promise<HealthAvailability>;
  requestAuthorization(options: { kinds: HealthKind[] }): Promise<HealthAuthorization>;
  read(options: { kinds: HealthKind[]; from: string; to: string }): Promise<RawHealthRead>;
  /** Android only: Play Store on Health Connect. */
  openInstaller?(): Promise<void>;
};

const PROVIDERS: Record<NativePlatform, PhoneHealthProvider> = { ios: "apple_health", android: "health_connect" };

/** The phone-health provider of this app install, or null (browsers, apps without the plugin). */
export function phoneHealthProvider(platform: NativePlatform | null = nativePlatform()): PhoneHealthProvider | null {
  if (!platform) return null;
  return hasCapability(platform === "ios" ? "healthKit" : "healthConnect") ? PROVIDERS[platform] : null;
}

let pluginPromise: Promise<MilosHealthPlugin> | null = null;

export function healthPlugin(): Promise<MilosHealthPlugin> {
  pluginPromise ??= import("@capacitor/core").then(({ registerPlugin }) => registerPlugin<MilosHealthPlugin>("MilosHealth"));
  return pluginPromise;
}

/** The kinds a row's choices turn on. */
export function enabledKinds(prefs: Partial<Record<HealthKind, boolean>> | null | undefined): HealthKind[] {
  return (["activities", "sleep", "weight", "resting_hr", "steps"] as HealthKind[]).filter((kind) => prefs?.[kind] !== false);
}

/**
 * The choices to save after the phone's permission sheet: on Android, kinds
 * the person refused there are switched off; iOS does not say, so the
 * choices stay and refused kinds simply read as empty.
 */
export function grantedPrefs(prefs: Record<HealthKind, boolean>, authorization: HealthAuthorization): Record<HealthKind, boolean> {
  if (authorization.granted === null) return prefs;
  const granted = new Set(authorization.granted);
  return Object.fromEntries(Object.entries(prefs).map(([kind, on]) => [kind, on && granted.has(kind as HealthKind)])) as Record<HealthKind, boolean>;
}

// Automatic syncs at most this often (app start and every return to it).
export const AUTO_SYNC_MINUTES = 15;
const HISTORY_DAYS = 30;

export function autoSyncDue(lastSyncedAt: string | null | undefined, now: Date = new Date()): boolean {
  if (!lastSyncedAt) return true;
  const last = Date.parse(lastSyncedAt);
  return Number.isNaN(last) || now.getTime() - last >= AUTO_SYNC_MINUTES * 60_000;
}

/** The window to read: from where the server says, to now. */
export function syncWindow(row: Pick<PhoneHealthRow, "connection" | "history_days">, now: Date = new Date()): { from: string; to: string } {
  const days = row.history_days ?? HISTORY_DAYS;
  const fallback = new Date(now.getTime() - days * 86_400_000);
  const readFrom = row.connection?.read_from ? new Date(row.connection.read_from) : fallback;
  const from = Number.isNaN(readFrom.getTime()) || readFrom >= now ? fallback : readFrom;
  return { from: from.toISOString(), to: now.toISOString() };
}

export type SyncResult = { counts: Record<string, number>; row: PhoneHealthRow | null; batches: number };

let inflight: Promise<SyncResult> | null = null;

/**
 * Reads the window from the phone and sends it in batches. One sync at a
 * time on this install, whoever asks (the app opening, «Συγχρονισμός τώρα»).
 */
export function syncPhoneHealth(token: string, row: PhoneHealthRow, plugin?: MilosHealthPlugin, now: Date = new Date()): Promise<SyncResult> {
  inflight ??= (async () => {
    const health = plugin ?? (await healthPlugin());
    const kinds = enabledKinds(row.connection?.sync_prefs ?? row.sync_prefs);
    const result: SyncResult = { counts: {}, row: null, batches: 0 };
    if (!kinds.length) return result;
    const read = await health.read({ kinds, ...syncWindow(row, now) });
    // An empty read still reports in, so the row's last sync moves on.
    const batches = toIngestBatches(read);
    for (const batch of batches.length ? batches : [{}]) {
      const response = await ingestPhoneHealth(token, row.provider, batch);
      result.batches += 1;
      result.row = response.row;
      for (const [status, count] of Object.entries(response.counts ?? {})) {
        result.counts[status] = (result.counts[status] ?? 0) + count;
      }
    }
    return result;
  })().finally(() => {
    inflight = null;
  });
  return inflight;
}

/** How many records were new (imported or merged into an entry). */
export function newCount(counts: Record<string, number>): number {
  return (counts.imported ?? 0) + (counts.merged ?? 0) + (counts.needs_confirmation ?? 0);
}
