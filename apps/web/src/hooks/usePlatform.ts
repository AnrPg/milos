"use client";

import { useSyncExternalStore } from "react";

import { CAPABILITIES, getCapabilities, nativePlatform, type Capabilities, type NativePlatform } from "@/lib/platform";

export type PlatformInfo = { platform: NativePlatform | null; capabilities: Capabilities };

const WEB: PlatformInfo = {
  platform: null,
  capabilities: Object.fromEntries(CAPABILITIES.map((capability) => [capability, false])) as Capabilities,
};

let cached: PlatformInfo | null = null;

function snapshot(): PlatformInfo {
  if (!cached) {
    const platform = nativePlatform();
    cached = platform ? { platform, capabilities: getCapabilities() } : WEB;
  }
  return cached;
}

const subscribe = () => () => {};

/**
 * ADR-171: the device this page runs on (`platform` null on the web) and its
 * native capabilities. The server render and the first client render agree
 * (web), so there is no hydration mismatch.
 */
export function usePlatform(): PlatformInfo {
  return useSyncExternalStore(subscribe, snapshot, () => WEB);
}
