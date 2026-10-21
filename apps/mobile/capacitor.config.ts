import type { CapacitorConfig } from "@capacitor/cli";

// ADR-171: the store apps are a native shell around the deployed web app
// (same code, same deploy). The web view loads `server.url` for the chosen
// environment; `www/` only holds the page shown when it cannot be reached.
// PALEE_APP_ENV (production | staging | development) and PALEE_APP_URL pick
// the URL at `cap sync` time.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { resolveEnvironment } = require("./config/resolve.cjs");

// eslint-disable-next-line @typescript-eslint/no-require-imports
const theme = require("./palee-theme.json"); // generated from the web theme (npm run theme:native)

const environment = resolveEnvironment();

const config: CapacitorConfig = {
  appId: environment.appId,
  appName: environment.appName,
  webDir: "www",
  // Lets the server tell the app apart in logs; the web detects the app
  // through the native bridge, never through this string.
  appendUserAgent: "PaleeApp",
  server: {
    url: environment.url,
    cleartext: environment.cleartext,
    // Hosts that may open inside the web view; everything else opens in the
    // system browser.
    allowNavigation: environment.navigationHosts,
    errorPath: "offline.html",
  },
  ios: {
    // App-bound domains let the web view keep its service worker (offline
    // workout cache, push of the web build) on iOS.
    limitsNavigationsToAppBoundDomains: true,
    contentInset: "never",
  },
  android: {
    allowMixedContent: false,
  },
  plugins: {
    SplashScreen: {
      launchAutoHide: true,
      launchShowDuration: 600,
      backgroundColor: theme.light.background,
      showSpinner: false,
    },
    PushNotifications: {
      presentationOptions: ["badge", "sound", "alert"],
    },
    SystemBars: {
      insetsHandling: "css",
    },
  },
};

export default config;
