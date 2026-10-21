// ADR-171: what the device the web app runs on can do.
//
// The store apps load this same web app inside a native shell (Capacitor).
// The shell injects its bridge as `window.Capacitor`, so detection reads that
// global and never imports @capacitor/core: on the web nothing extra is
// downloaded. Native plugins are imported lazily, only inside the app.

export type NativePlatform = "ios" | "android";

export type Capability = "nativePush" | "healthKit" | "healthConnect" | "widgets" | "geofence" | "nfc";

export type Capabilities = Record<Capability, boolean>;

type CapacitorBridge = {
  isNativePlatform?: () => boolean;
  getPlatform?: () => string;
  isPluginAvailable?: (name: string) => boolean;
};

// Each capability is a native plugin on given platforms. Push ships now;
// the others arrive with P3-M10 (Apple Health, Health Connect) and P3-M11
// (widgets, geofence, NFC) and light up as soon as their plugin is present.
const CAPABILITY_PLUGINS: Record<Capability, { plugin: string; platforms: NativePlatform[] }> = {
  nativePush: { plugin: "PushNotifications", platforms: ["ios", "android"] },
  healthKit: { plugin: "MilosHealth", platforms: ["ios"] },
  healthConnect: { plugin: "MilosHealth", platforms: ["android"] },
  widgets: { plugin: "MilosWidgets", platforms: ["ios", "android"] },
  geofence: { plugin: "MilosGeofence", platforms: ["ios", "android"] },
  nfc: { plugin: "MilosNfc", platforms: ["ios", "android"] },
};

export const CAPABILITIES = Object.keys(CAPABILITY_PLUGINS) as Capability[];

function bridge(): CapacitorBridge | null {
  if (typeof window === "undefined") return null;
  const candidate = (window as unknown as { Capacitor?: CapacitorBridge }).Capacitor;
  return candidate && typeof candidate === "object" ? candidate : null;
}

/** True inside the iOS or Android app, false in any browser (and on the server). */
export function isNative(): boolean {
  try {
    return bridge()?.isNativePlatform?.() === true;
  } catch {
    return false;
  }
}

/** `ios` or `android` inside the app, otherwise null. */
export function nativePlatform(): NativePlatform | null {
  if (!isNative()) return null;
  const platform = bridge()?.getPlatform?.();
  return platform === "ios" || platform === "android" ? platform : null;
}

export function hasCapability(capability: Capability): boolean {
  const platform = nativePlatform();
  if (!platform) return false;
  const { plugin, platforms } = CAPABILITY_PLUGINS[capability];
  if (!platforms.includes(platform)) return false;
  try {
    return bridge()?.isPluginAvailable?.(plugin) === true;
  } catch {
    return false;
  }
}

/** Every capability; all false on the web. */
export function getCapabilities(): Capabilities {
  return Object.fromEntries(CAPABILITIES.map((capability) => [capability, hasCapability(capability)])) as Capabilities;
}

/** The push provider of this app install: APNs on iOS, FCM on Android. */
export function nativePushProvider(): "apns" | "fcm" | null {
  const platform = nativePlatform();
  if (platform === "ios") return "apns";
  if (platform === "android") return "fcm";
  return null;
}
