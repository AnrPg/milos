
import { Suspense } from "react";
import {getUiTranslations} from "@/i18n/ui-server";
import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { getLocale, getTimeZone } from "next-intl/server";
import { ClientMessagesProvider } from "@/i18n/client-messages-provider";
import { QueryProvider } from "@/components/query-provider";
import { BuddyRealtimeBridge } from "@/components/buddy/BuddyRealtimeBridge";
import { RealtimeSyncBridge } from "@/components/realtime-sync-bridge";
import { OfflineMessageSyncBridge } from "@/components/offline-message-sync-bridge";
import { OutboxStatusPanel } from "@/components/outbox/OutboxStatusPanel";
import { SessionProvider } from "@/components/session-provider";
import { ServiceWorkerBootstrap } from "@/components/service-worker-bootstrap";
import { PersonalThemeBridge, ThemeProvider } from "@/components/theme-provider";
import { TopNav } from "@/components/TopNav";
import { EmailVerificationBanner } from "@/components/auth/EmailVerificationBanner";
import { BottomNav } from "@/components/nav/BottomNav";
import { ScreenPreloader } from "@/components/nav/ScreenPreloader";
import { OnboardingHost } from "@/components/onboarding/Onboarding";
import { DemoModeHost } from "@/components/business/DemoModeHost";
import { GuideOffer } from "@/components/guides/GuideOffer";
import { GuideOverlay } from "@/components/guides/GuideOverlay";
import { GuideProvider } from "@/components/guides/GuideProvider";
import { ReferralClaimBridge } from "@/components/referrals/ReferralClaimBridge";
import { NativeAppBridge } from "@/components/platform/NativeAppBridge";
import { PhoneHealthSyncBridge } from "@/components/platform/PhoneHealthSyncBridge";
import { WidgetsGeofenceBridge } from "@/components/platform/WidgetsGeofenceBridge";
import { APP_THEMES, DEFAULT_THEME_SLUG, THEME_SLUGS, THEME_STORAGE_KEY, themeStylesheet } from "@/lib/theme";
import { isAppLocale, localeDirection } from "@/i18n/locales";
import "@fontsource-variable/commissioner";
import "./globals.css";
import { HydrationMarker } from "@/components/HydrationMarker";
import { siteOrigin } from "@/lib/site-url";
import { JsonLd } from "@/components/seo/JsonLd";
import { loadSiteFacts } from "@/lib/seo/site-facts";
import { siteStructuredData } from "@/lib/seo/site-info";

export async function generateMetadata(): Promise<Metadata> {
  const i18n = await getUiTranslations();
  const brand = i18n("brandName");
  const description = i18n("gymSchedulingAthleteProgrammingAndWorkoutExecution7f2b88a");
  return {
    metadataBase: await siteOrigin(),
    applicationName: brand,
    title: brand,
    description,
    // Search engines and link previews name the product from these, not only
    // from <title>.
    openGraph: { type: "website", siteName: brand, title: brand, description },
    twitter: { card: "summary_large_image", title: brand, description },
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
  // The on-screen keyboard shrinks the layout viewport, so dialogs sized to
  // 100dvh keep their footer actions above it instead of under it.
  interactiveWidget: "resizes-content",
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
  const timeZone = await getTimeZone();
  const { facts } = await loadSiteFacts();

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
        <JsonLd data={siteStructuredData(facts)} />
      </head>
      {/* --bottom-nav-space (globals.css): room for the member app's floating bar. */}
      <body className="min-h-full flex flex-col pb-(--bottom-nav-space)">
        <ClientMessagesProvider locale={locale} timeZone={timeZone}>
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
                {/* ADR-193: in-app walkthroughs; the overlay survives page changes. */}
                <GuideProvider>
                  <TopNav />
                  {/* ADR-213: the quiet "confirm your email" line. */}
                  <EmailVerificationBanner />
                  {children}
                  <BottomNav />
                  <ScreenPreloader />
                  <OnboardingHost />
                  <DemoModeHost />
                  <Suspense fallback={null}>
                    <GuideOffer />
                    <GuideOverlay />
                  </Suspense>
                </GuideProvider>
                <HydrationMarker />
              </SessionProvider>
            </ThemeProvider>
          </QueryProvider>
        </ClientMessagesProvider>
      </body>
    </html>
  );
}
