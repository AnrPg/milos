
import {getUiTranslations} from "@/i18n/ui-server";
import type { Metadata } from "next";
import { headers } from "next/headers";
import { NextIntlClientProvider } from "next-intl";
import { getLocale, getMessages } from "next-intl/server";
import { QueryProvider } from "@/components/query-provider";
import { RealtimeSyncBridge } from "@/components/realtime-sync-bridge";
import { SessionProvider } from "@/components/session-provider";
import { ServiceWorkerBootstrap } from "@/components/service-worker-bootstrap";
import { ThemeProvider } from "@/components/theme-provider";
import { TopNav } from "@/components/TopNav";
import { APP_THEMES, cssVariablesForTheme, DEFAULT_THEME_SLUG, THEME_STORAGE_KEY } from "@/lib/theme";
import { isAppLocale, localeDirection } from "@/i18n/locales";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const i18n = await getUiTranslations();
  return {
    title: i18n("milosTraining5b1a1c1"),
    description: i18n("gymSchedulingAthleteProgrammingAndWorkoutExecution7f2b88a"),
    manifest: "/manifest.webmanifest",
    icons: {
      icon: "/icon.svg",
      apple: "/icon.svg",
    },
  };
}

const initialThemeVariablesBySlug = Object.fromEntries(
  Object.values(APP_THEMES).map((theme) => [theme.slug, cssVariablesForTheme(theme)]),
);

const themeBootstrapScript = `
(() => {
  const variablesByTheme = ${JSON.stringify(initialThemeVariablesBySlug)};
  const storageKey = ${JSON.stringify(THEME_STORAGE_KEY)};
  const defaultSlug = ${JSON.stringify(DEFAULT_THEME_SLUG)};
  let slug = defaultSlug;

  try {
    slug = window.localStorage.getItem(storageKey) || defaultSlug;
  } catch {
    slug = defaultSlug;
  }

  const variables = variablesByTheme[slug] || variablesByTheme[defaultSlug];
  const root = document.documentElement;
  root.dataset.theme = variablesByTheme[slug] ? slug : defaultSlug;

  for (const [name, value] of Object.entries(variables)) {
    root.style.setProperty(name, value);
  }
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
        <script
          nonce={nonce}
          suppressHydrationWarning
          dangerouslySetInnerHTML={{ __html: themeBootstrapScript }}
        />
      </head>
      <body className="min-h-full flex flex-col" style={{ background: "var(--bg)" }}>
        <NextIntlClientProvider locale={locale} messages={messages}>
          <QueryProvider>
            <ThemeProvider>
              <SessionProvider>
                <RealtimeSyncBridge />
                <ServiceWorkerBootstrap />
                <TopNav />
                {children}
              </SessionProvider>
            </ThemeProvider>
          </QueryProvider>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
