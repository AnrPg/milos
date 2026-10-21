import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

import { androidIntentFilter, iosAppBoundDomains, replaceBetweenMarkers, withEntitlementsSetting } from "./configure.mjs";

const require = createRequire(import.meta.url);
const { resolveEnvironment, appLinkPathPrefixes } = require("../config/resolve.cjs");

const xml = { open: "<!--", close: "-->" };

test("production loads the https web app and allows its host", () => {
  const env = resolveEnvironment({ PALEE_APP_ENV: "production" });
  assert.equal(env.url, "https://milos.4kq.net");
  assert.equal(env.appId, "app.milos.member");
  assert.equal(env.cleartext, false);
  assert.ok(env.navigationHosts.includes("milos.4kq.net"));
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
