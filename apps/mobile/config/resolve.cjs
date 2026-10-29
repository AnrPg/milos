// ADR-171: resolves which deployed web app a build of the store apps loads.
// CommonJS so both capacitor.config.ts (transpiled by the Capacitor CLI) and
// the ESM scripts can use it. No dependencies.
const fs = require("node:fs");
const path = require("node:path");

const configDir = __dirname;
const settings = JSON.parse(fs.readFileSync(path.join(configDir, "environments.json"), "utf8"));
const appLinksFile = path.join(configDir, "..", "..", "web", "src", "lib", "platform", "app-links.json");

function resolveEnvironment(env = process.env) {
  const name = (env.PALEE_APP_ENV || "production").trim();
  const entry = settings.environments[name];
  if (!entry) {
    throw new Error(`PALEE_APP_ENV=${name} is not one of ${Object.keys(settings.environments).join(", ")}`);
  }

  const rawUrl = (env.PALEE_APP_URL || "").trim() || entry.url;
  if (!rawUrl) {
    throw new Error(`No web app URL for ${name}: set PALEE_APP_URL`);
  }

  const url = new URL(rawUrl);
  if (url.protocol !== "https:" && name === "production") {
    throw new Error("The production app must load an https URL");
  }

  const extraHosts = (env.PALEE_EXTRA_NAVIGATION_HOSTS || "")
    .split(",")
    .map((host) => host.trim())
    .filter(Boolean);

  return {
    name,
    appId: (env.PALEE_APP_ID || "").trim() || settings.appId,
    appName: settings.appName,
    url: url.origin,
    host: url.host,
    hostname: url.hostname,
    cleartext: url.protocol === "http:",
    navigationHosts: [...new Set([url.host, ...settings.extraNavigationHosts, ...extraHosts])],
  };
}

function appLinkPathPrefixes() {
  return JSON.parse(fs.readFileSync(appLinksFile, "utf8")).pathPrefixes;
}

// Google Play refuses a versionCode above 2 100 000 000.
const MAX_BUILD = 2100000000;

/**
 * ADR-256: the store version (release.json) and the build number, which
 * PALEE_BUILD_NUMBER may override for one build. The version is three
 * dot-separated numbers (Apple allows no more); the build a whole number
 * from 1 that only goes up.
 */
function resolveRelease(env = process.env, release = JSON.parse(fs.readFileSync(path.join(configDir, "release.json"), "utf8"))) {
  const version = String(release.version ?? "").trim();
  if (!/^(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})$/.test(version)) {
    throw new Error(`release.json version must look like 3.0.0, got "${version}"`);
  }

  const rawBuild = (env.PALEE_BUILD_NUMBER || "").trim() || String(release.build ?? "");
  if (!/^[1-9]\d*$/.test(rawBuild) || Number(rawBuild) > MAX_BUILD) {
    throw new Error(`The build number must be a whole number from 1 to ${MAX_BUILD}, got "${rawBuild}"`);
  }

  return { version, build: Number(rawBuild) };
}

module.exports = { resolveEnvironment, appLinkPathPrefixes, resolveRelease };
