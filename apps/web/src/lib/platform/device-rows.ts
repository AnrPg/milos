// ADR-171: how the phone-health rows of «Συνδεδεμένες συσκευές» read on
// this device. On the web both rows keep «Με την εφαρμογή». Inside the app
// only this phone's row shows (Apple Health on iOS, Health Connect on
// Android); it reads «Σύντομα» until the health plugin ships (P3-M10).
import type { Capabilities, NativePlatform } from "./index";

export type PhoneHealthProvider = "apple_health" | "health_connect";

const PROVIDER_PLATFORM: Record<PhoneHealthProvider, { platform: NativePlatform; capability: keyof Capabilities }> = {
  apple_health: { platform: "ios", capability: "healthKit" },
  health_connect: { platform: "android", capability: "healthConnect" },
};

export function isPhoneHealthProvider(provider: string): provider is PhoneHealthProvider {
  return provider in PROVIDER_PLATFORM;
}

/** Drops the other platform's phone-health row inside the app. */
export function visibleIntegrations<T extends { provider: string }>(integrations: T[], platform: NativePlatform | null): T[] {
  if (!platform) return integrations;
  return integrations.filter(
    (integration) => !isPhoneHealthProvider(integration.provider) || PROVIDER_PLATFORM[integration.provider].platform === platform,
  );
}

/**
 * The status key a `native_only` row shows: unchanged on the web, `native_soon`
 * inside an app that does not have the health plugin yet.
 */
export function integrationStatusKey(
  integration: { provider: string; status: string },
  platform: NativePlatform | null,
  capabilities: Capabilities,
): string {
  if (!platform || integration.status !== "native_only" || !isPhoneHealthProvider(integration.provider)) {
    return integration.status;
  }
  return capabilities[PROVIDER_PLATFORM[integration.provider].capability] ? "native_only" : "native_soon";
}
