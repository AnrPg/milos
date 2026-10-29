// ADR-256: checks that the native projects keep what the stores require.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

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

test("Android declares the camera the web view uses, without requiring a camera", () => {
  assert.match(manifest, /android\.permission\.CAMERA/);
  assert.match(manifest, /android\.hardware\.camera" android:required="false"/);
  assert.match(manifest, /android\.permission\.POST_NOTIFICATIONS/);
});
