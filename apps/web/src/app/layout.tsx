
import {getUiTranslations} from "@/i18n/ui-server";
import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { NextIntlClientProvider } from "next-intl";
import { getLocale, getMessages } from "next-intl/server";
import { QueryProvider } from "@/components/query-provider";
import { BuddyRealtimeBridge } from "@/components/buddy/BuddyRealtimeBridge";
import { RealtimeSyncBridge } from "@/components/realtime-sync-bridge";
import { OfflineMessageSyncBridge } from "@/components/offline-message-sync-bridge";
import { OutboxStatusPanel } from "@/components/outbox/OutboxStatusPanel";
import { SessionProvider } from "@/components/session-provider";
import { ServiceWorkerBootstrap } from "@/components/service-worker-bootstrap";
import { PersonalThemeBridge, ThemeProvider } from "@/components/theme-provider";
import { TopNav } from "@/components/TopNav";
import { BottomTabBar } from "@/components/nav/BottomTabBar";
import { OnboardingHost } from "@/components/onboarding/Onboarding";
import { ReferralClaimBridge } from "@/components/referrals/ReferralClaimBridge";
import { NativeAppBridge } from "@/components/platform/NativeAppBridge";
import { PhoneHealthSyncBridge } from "@/components/platform/PhoneHealthSyncBridge";
import { WidgetsGeofenceBridge } from "@/components/platform/WidgetsGeofenceBridge";
import { APP_THEMES, DEFAULT_THEME_SLUG, THEME_SLUGS, THEME_STORAGE_KEY, themeStylesheet } from "@/lib/theme";
import { isAppLocale, localeDirection } from "@/i18n/locales";
import "@fontsource-variable/commissioner";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const i18n = await getUiTranslations();
  return {
    title: i18n("brandName"),
    description: i18n("gymSchedulingAthleteProgrammingAndWorkoutExecution7f2b88a"),
    manifest: "/manifest.webmanifest",
    icons: {
      icon: "/icon.svg",
      apple: "/icon.svg",
    },
  };
}

// ADR-171: draw under the notch and home indicator (in the store apps and an
// installed PWA); headers, sheets and the tab bar pad with env(safe-area-inset-*).
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  // The browser and status bar colour; ThemeProvider keeps it in step with
  // the member's light or dark choice.
  themeColor: APP_THEMES[DEFAULT_THEME_SLUG].tokens.bg,
};

// Every theme variable, generated from src/lib/theme.ts (the only place
// colours are defined); the bootstrap script picks the stored theme before
// first paint.
const themeCss = themeStylesheet();

const themeBootstrapScript = `
(() => {
  const slugs = ${JSON.stringify(THEME_SLUGS)};
  const storageKey = ${JSON.stringify(THEME_STORAGE_KEY)};
  const defaultSlug = ${JSON.stringify(DEFAULT_THEME_SLUG)};
  let slug = defaultSlug;

  try {
    slug = window.localStorage.getItem(storageKey) || defaultSlug;
  } catch {
    slug = defaultSlug;
  }

  const root = document.documentElement;
  root.dataset.theme = slugs.includes(slug) ? slug : defaultSlug;

  // ADR-171: mark the store apps before first paint (safe-area padding).
  try {
    const bridge = window.Capacitor;
    if (bridge && bridge.isNativePlatform && bridge.isNativePlatform()) {
      root.dataset.platform = bridge.getPlatform();
    }
  } catch {}
})();
`;

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const nonce = (await headers()).get("x-nonce") ?? undefined;
  const resolvedLocale = await getLocale();
  const locale = isAppLocale(resolvedLocale) ? resolvedLocale : "en";
  const messages = await getMessages();

  return (
    <html
      lang={locale}
      dir={localeDirection(locale)}
      className="h-full antialiased"
      suppressHydrationWarning
    >
      <head>
        <style id="palee-theme" dangerouslySetInnerHTML={{ __html: themeCss }} />
        <script
          nonce={nonce}
          suppressHydrationWarning
          dangerouslySetInnerHTML={{ __html: themeBootstrapScript }}
        />
      </head>
      <body className="min-h-full flex flex-col">
        <NextIntlClientProvider locale={locale} messages={messages}>
          <QueryProvider>
            <ThemeProvider>
              <SessionProvider>
                <PersonalThemeBridge />
                <RealtimeSyncBridge />
                <BuddyRealtimeBridge />
                <OfflineMessageSyncBridge />
                <OutboxStatusPanel />
                <ServiceWorkerBootstrap />
                <ReferralClaimBridge />
                <NativeAppBridge />
                <PhoneHealthSyncBridge />
                <WidgetsGeofenceBridge />
                <TopNav />
                {children}
                <BottomTabBar />
                <OnboardingHost />
              </SessionProvider>
            </ThemeProvider>
          </QueryProvider>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
