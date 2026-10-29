// ADR-256: checks that the native projects keep what the stores require.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { privacyManifest } from "./configure.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

const infoPlist = read("ios/App/App/Info.plist");
const pbxproj = read("ios/App/App.xcodeproj/project.pbxproj");
const manifest = read("android/app/src/main/AndroidManifest.xml");

function plistKeys(source, pattern) {
  return [...source.matchAll(/<key>([^<]+)<\/key>/g)].map((match) => match[1]).filter((key) => pattern.test(key));
}

function stringsFile(language) {
  const source = read(`ios/App/App/${language}.lproj/InfoPlist.strings`);
  return Object.fromEntries([...source.matchAll(/^"([^"]+)" = "((?:[^"\\]|\\.)*)";$/gm)].map((match) => [match[1], match[2]]));
}

test("every permission iOS may ask for has a reason in Info.plist, in English and in Greek", () => {
  const purposeKeys = plistKeys(infoPlist, /UsageDescription$/);
  for (const required of [
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSHealthShareUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NFCReaderUsageDescription",
  ]) {
    assert.ok(purposeKeys.includes(required), `${required} is missing from Info.plist`);
  }

  const english = stringsFile("en");
  const greek = stringsFile("el");
  for (const key of purposeKeys) {
    assert.ok(english[key]?.length > 20, `${key} has no English text`);
    assert.ok(greek[key]?.length > 20, `${key} has no Greek text`);
    assert.match(greek[key], /[α-ωά-ώ]/, `${key} is not in Greek`);
    assert.ok(infoPlist.includes(`<string>${english[key].replaceAll('\\"', '"')}</string>`), `${key}: Info.plist and en.lproj differ`);
  }
});

test("the Greek and English permission texts are part of the app target", () => {
  assert.match(pbxproj, /InfoPlist\.strings in Resources/);
  assert.match(pbxproj, /path = el\.lproj\/InfoPlist\.strings;/);
  assert.match(pbxproj, /path = en\.lproj\/InfoPlist\.strings;/);
  assert.match(pbxproj, /knownRegions = \(\n(?:\s+\w+,\n)*\s+el,/);
});

test("the privacy manifests are the ones generated from config/data-collection.json", () => {
  const collection = JSON.parse(read("config/data-collection.json"));
  assert.equal(read("ios/App/App/PrivacyInfo.xcprivacy"), privacyManifest(collection, "app"));
  assert.equal(read("ios/App/PaleeWidgets/PrivacyInfo.xcprivacy"), privacyManifest(collection, "widgets"));
  assert.match(pbxproj, /PrivacyInfo\.xcprivacy in Resources/);
});

test("the privacy manifest declares no tracking and every collected type once", () => {
  const collection = JSON.parse(read("config/data-collection.json"));
  const manifest = privacyManifest(collection, "app");
  assert.equal(collection.tracking, false);
  assert.doesNotMatch(manifest, /<key>NSPrivacyCollectedDataTypeTracking<\/key>\n\t+<true\/>/);
  const declared = [...manifest.matchAll(/<string>(NSPrivacyCollectedDataType(?!Purpose)\w+)<\/string>/g)].map((match) => match[1]);
  assert.deepEqual([...declared].sort(), [...new Set(collection.items.map((item) => item.apple))].sort());
  for (const type of ["NSPrivacyCollectedDataTypeHealth", "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypePurchaseHistory"]) {
    assert.ok(declared.includes(type), `${type} is not declared`);
  }
  assert.match(manifest, /NSPrivacyAccessedAPICategoryUserDefaults/);
  assert.match(manifest, /<string>CA92\.1<\/string>/);
  assert.throws(() => privacyManifest({ tracking: false, items: [{ id: "x", apple: "T", purposes: ["ads"] }] }), /Unknown purpose/);
});

test("every collected item maps to a Google Play Data safety category and type", () => {
  const categories = new Set([
    "Location",
    "Personal info",
    "Financial info",
    "Health and fitness",
    "Messages",
    "Photos and videos",
    "Audio",
    "Files and docs",
    "Calendar",
    "Contacts",
    "App activity",
    "Web browsing",
    "App info and performance",
    "Device or other IDs",
  ]);
  for (const item of JSON.parse(read("config/data-collection.json")).items) {
    assert.ok(categories.has(item.google?.[0]), `${item.id}: unknown Data safety category ${item.google?.[0]}`);
    assert.ok(item.google[1], `${item.id}: no Data safety type`);
    assert.equal(typeof item.required, "boolean", `${item.id}: required or optional?`);
  }
});

test("Android declares the camera the web view uses, without requiring a camera", () => {
  assert.match(manifest, /android\.permission\.CAMERA/);
  assert.match(manifest, /android\.hardware\.camera" android:required="false"/);
  assert.match(manifest, /android\.permission\.POST_NOTIFICATIONS/);
});

test("push messages use Palee's icon and a named channel in English and Greek", () => {
  assert.match(manifest, /default_notification_icon"\s+android:resource="@drawable\/ic_stat_palee"/);
  assert.match(manifest, /default_notification_channel_id"\s+android:value="@string\/palee_push_channel_id"/);
  assert.match(read("android/app/src/main/res/values/palee_push.xml"), /palee_push_channel_name">Palee notifications</);
  assert.match(read("android/app/src/main/res/values-el/palee_push.xml"), /palee_push_channel_name">Ειδοποιήσεις Palee</);
  assert.match(read("android/app/src/main/java/app/palee/member/MainActivity.java"), /createNotificationChannel/);
  assert.match(read("ios/App/App/App.entitlements"), /<key>aps-environment<\/key>/);
});

test("the app's data is not backed up to the cloud", () => {
  assert.match(manifest, /android:allowBackup="false"/);
});
