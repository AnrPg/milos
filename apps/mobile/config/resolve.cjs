// ADR-171: resolves which deployed web app a build of the store apps loads.
// CommonJS so both capacitor.config.ts (transpiled by the Capacitor CLI) and
// the ESM scripts can use it. No dependencies.
const fs = require("node:fs");
const path = require("node:path");

const configDir = __dirname;
const settings = JSON.parse(fs.readFileSync(path.join(configDir, "environments.json"), "utf8"));
const appLinksFile = path.join(configDir, "..", "..", "web", "src", "lib", "platform", "app-links.json");

function resolveEnvironment(env = process.env) {
  const name = (env.MILOS_APP_ENV || "production").trim();
  const entry = settings.environments[name];
  if (!entry) {
    throw new Error(`MILOS_APP_ENV=${name} is not one of ${Object.keys(settings.environments).join(", ")}`);
  }

  const rawUrl = (env.MILOS_APP_URL || "").trim() || entry.url;
  if (!rawUrl) {
    throw new Error(`No web app URL for ${name}: set MILOS_APP_URL`);
  }

  const url = new URL(rawUrl);
  if (url.protocol !== "https:" && name === "production") {
    throw new Error("The production app must load an https URL");
  }

  const extraHosts = (env.MILOS_EXTRA_NAVIGATION_HOSTS || "")
    .split(",")
    .map((host) => host.trim())
    .filter(Boolean);

  return {
    name,
    appId: (env.MILOS_APP_ID || "").trim() || settings.appId,
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

module.exports = { resolveEnvironment, appLinkPathPrefixes };
