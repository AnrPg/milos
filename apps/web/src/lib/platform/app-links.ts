// ADR-171: universal links (iOS) and App Links (Android) for the share links.
// The list lives in app-links.json so the store apps' build script reads the
// same prefixes.
import appLinks from "./app-links.json";

export const APP_LINK_PATH_PREFIXES: readonly string[] = appLinks.pathPrefixes;

type Env = Record<string, string | undefined>;

function list(value: string | undefined) {
  return (value ?? "")
    .split(/[\s,]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

/**
 * The apple-app-site-association document, or null until the Apple team id
 * is configured (APPLE_TEAM_ID; IOS_BUNDLE_ID defaults to app.milos.member).
 */
export function appleAppSiteAssociation(env: Env = process.env) {
  const teamId = env.APPLE_TEAM_ID?.trim();
  if (!teamId) return null;
  const bundleIds = list(env.IOS_BUNDLE_ID);
  const appIDs = (bundleIds.length ? bundleIds : ["app.milos.member"]).map((bundleId) => `${teamId}.${bundleId}`);

  return {
    applinks: {
      details: [
        {
          appIDs,
          components: APP_LINK_PATH_PREFIXES.map((prefix) => ({ "/": `${prefix}*` })),
        },
      ],
    },
    webcredentials: { apps: appIDs },
  };
}

/**
 * The Digital Asset Links statement list, or null until the signing
 * certificate fingerprints are configured (ANDROID_SHA256_CERT_FINGERPRINTS,
 * comma separated; ANDROID_PACKAGE_NAME defaults to app.milos.member).
 */
export function assetLinks(env: Env = process.env) {
  const fingerprints = list(env.ANDROID_SHA256_CERT_FINGERPRINTS).map((value) => value.toUpperCase());
  if (fingerprints.length === 0) return null;
  const packageName = env.ANDROID_PACKAGE_NAME?.trim() || "app.milos.member";

  return [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: { namespace: "android_app", package_name: packageName, sha256_cert_fingerprints: fingerprints },
    },
  ];
}

/**
 * The in-app path for a link the system opened the app with, only when it
 * points at this web app's own host (anything else is ignored).
 */
export function inAppPath(url: string, currentOrigin: string): string | null {
  try {
    const target = new URL(url);
    const origin = new URL(currentOrigin);
    if (target.host !== origin.host || !/^https?:$/.test(target.protocol)) return null;
    return `${target.pathname}${target.search}${target.hash}` || "/";
  } catch {
    return null;
  }
}

/** A notification's link as an in-app path: relative paths, or absolute ones on this host. */
export function notificationPath(url: unknown, currentOrigin: string): string | null {
  if (typeof url !== "string" || url === "") return null;
  if (url.startsWith("/") && !url.startsWith("//")) return url;
  return inAppPath(url, currentOrigin);
}
