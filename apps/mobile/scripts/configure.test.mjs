import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

import {
  androidIntentFilter,
  iosAppBoundDomains,
  replaceBetweenMarkers,
  withAndroidVersion,
  withEntitlementsSetting,
  withIosVersion,
} from "./configure.mjs";

const require = createRequire(import.meta.url);
const { resolveEnvironment, appLinkPathPrefixes, resolveRelease } = require("../config/resolve.cjs");

const xml = { open: "<!--", close: "-->" };

test("production loads the https web app and allows its host", () => {
  const env = resolveEnvironment({ PALEE_APP_ENV: "production" });
  assert.equal(env.url, "https://palee.app");
  assert.equal(env.appId, "app.palee.member");
  assert.equal(env.cleartext, false);
  assert.ok(env.navigationHosts.includes("palee.app"));
});

test("PALEE_APP_URL overrides the URL and production refuses http", () => {
  assert.equal(resolveEnvironment({ PALEE_APP_ENV: "staging", PALEE_APP_URL: "https://staging.example.test/x" }).url, "https://staging.example.test");
  assert.throws(() => resolveEnvironment({ PALEE_APP_ENV: "production", PALEE_APP_URL: "http://plain.example.test" }));
  assert.throws(() => resolveEnvironment({ PALEE_APP_ENV: "staging" }), /PALEE_APP_URL/);
  assert.throws(() => resolveEnvironment({ PALEE_APP_ENV: "nope" }));
});

test("development may use cleartext", () => {
  assert.equal(resolveEnvironment({ PALEE_APP_ENV: "development" }).cleartext, true);
});

test("the share links come from the web's list", () => {
  const prefixes = appLinkPathPrefixes();
  assert.ok(prefixes.includes("/c/"));
  assert.ok(prefixes.includes("/join/"));
  const filter = androidIntentFilter("palee.test", prefixes);
  assert.match(filter, /android:autoVerify="true"/);
  assert.match(filter, /android:host="palee.test"/);
  assert.match(filter, /android:pathPrefix="\/b\/"/);
});

test("marker blocks are inserted once and then replaced in place", () => {
  const manifest = "<activity>\n        <intent-filter />\n        </activity>\n";
  const first = replaceBetweenMarkers(manifest, "<a />", { ...xml, anchor: "</activity>" });
  const second = replaceBetweenMarkers(first, "<b />", { ...xml, anchor: "</activity>" });
  assert.equal((second.match(/palee:app-links begin/g) ?? []).length, 1);
  assert.match(second, /<b \/>/);
  assert.doesNotMatch(second, /<a \/>/);
  assert.equal(replaceBetweenMarkers(second, "<b />", { ...xml, anchor: "</activity>" }), second);
});

test("app-bound domains list every allowed host", () => {
  assert.match(iosAppBoundDomains(["a.test", "b.test"]), /<string>b.test<\/string>/);
});

test("the entitlements setting is added to both build configurations once", () => {
  const project = "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n";
  const once = withEntitlementsSetting(project);
  assert.equal((once.match(/CODE_SIGN_ENTITLEMENTS/g) ?? []).length, 2);
  assert.equal(withEntitlementsSetting(once), once);
});

test("the store version is 3.0.0 and the build number may come from the environment", () => {
  assert.deepEqual(resolveRelease({}), { version: "3.0.0", build: 1 });
  assert.deepEqual(resolveRelease({ PALEE_BUILD_NUMBER: " 42 " }), { version: "3.0.0", build: 42 });
  assert.throws(() => resolveRelease({ PALEE_BUILD_NUMBER: "0" }), /build number/);
  assert.throws(() => resolveRelease({ PALEE_BUILD_NUMBER: "1.5" }), /build number/);
  assert.throws(() => resolveRelease({ PALEE_BUILD_NUMBER: "2100000001" }), /build number/);
  assert.throws(() => resolveRelease({}, { version: "3.0", build: 1 }), /version/);
  assert.throws(() => resolveRelease({}, { version: "3.0.0.1", build: 1 }), /version/);
});

test("the version is written into Android's defaultConfig and every iOS configuration", () => {
  const release = { version: "3.0.0", build: 7 };
  const gradle = '    defaultConfig {\n        versionCode 1\n        versionName "1.0"\n    }\n';
  const nextGradle = withAndroidVersion(gradle, release);
  assert.match(nextGradle, /^ {8}versionCode 7$/m);
  assert.match(nextGradle, /^ {8}versionName "3.0.0"$/m);
  assert.equal(withAndroidVersion(nextGradle, release), nextGradle);

  const project = "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n\t\t\t\tMARKETING_VERSION = 1.0;\n\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n\t\t\t\tMARKETING_VERSION = 1.0;\n";
  const nextProject = withIosVersion(project, release);
  assert.equal((nextProject.match(/MARKETING_VERSION = 3\.0\.0;/g) ?? []).length, 2);
  assert.equal((nextProject.match(/CURRENT_PROJECT_VERSION = 7;/g) ?? []).length, 2);
});
