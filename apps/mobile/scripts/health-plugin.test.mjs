// ADR-172: the PaleeHealth plugin can't be compiled here, so these checks keep
// its wiring honest: the same methods and kinds on iOS, Android and the web
// wrapper, and every native file actually reachable by the app build.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

const swift = read("../ios/App/App/PaleeHealthPlugin.swift");
const kotlin = read("../android/app/src/main/java/app/palee/member/PaleeHealthPlugin.kt");
const web = read("../../web/src/lib/platform/health.ts");

const KINDS = ["activities", "sleep", "weight", "resting_hr", "steps"];
const METHODS = ["availability", "requestAuthorization", "read"];

test("iOS and Android expose the methods the web wrapper calls", () => {
  for (const method of METHODS) {
    assert.match(swift, new RegExp(`CAPPluginMethod\\(name: "${method}"`), `swift ${method}`);
    assert.match(kotlin, new RegExp(`@PluginMethod\\s+fun ${method}\\(`), `kotlin ${method}`);
    assert.match(web, new RegExp(`\\b${method}\\(`), `web ${method}`);
  }
  assert.match(kotlin, /@PluginMethod\s+fun openInstaller\(/);
  assert.match(swift, /jsName = "PaleeHealth"/);
  assert.match(kotlin, /@CapacitorPlugin\(name = "PaleeHealth"/);
  assert.match(web, /registerPlugin<[^>]*>\("PaleeHealth"\)|registerPlugin\("PaleeHealth"/);
});

test("every kind is known on both platforms", () => {
  for (const kind of KINDS) {
    assert.ok(swift.includes(`"${kind}"`), `swift ${kind}`);
    assert.ok(kotlin.includes(`"${kind}"`), `kotlin ${kind}`);
  }
});

test("the iOS plugin is compiled and registered", () => {
  const project = read("../ios/App/App.xcodeproj/project.pbxproj");
  for (const file of ["PaleeHealthPlugin.swift", "PaleeBridgeViewController.swift"]) {
    assert.match(project, new RegExp(`/\\* ${file} in Sources \\*/,`), `${file} in the Sources phase`);
    assert.match(project, new RegExp(`isa = PBXFileReference;[^}]*path = ${file};`), `${file} file reference`);
  }
  assert.match(read("../ios/App/App/Base.lproj/Main.storyboard"), /customClass="PaleeBridgeViewController" customModule="App"/);
  assert.match(read("../ios/App/App/PaleeBridgeViewController.swift"), /registerPluginInstance\(PaleeHealthPlugin\(\)\)/);
  assert.match(read("../ios/App/App/Info.plist"), /<key>NSHealthShareUsageDescription<\/key>/);
  assert.match(read("../ios/App/App/App.entitlements"), /<key>com\.apple\.developer\.healthkit<\/key>\s*<true\/>/);
});

test("the Android plugin is registered with its read permissions", () => {
  assert.match(read("../android/app/src/main/java/app/palee/member/MainActivity.java"), /registerPlugin\(PaleeHealthPlugin\.class\)/);
  const manifest = read("../android/app/src/main/AndroidManifest.xml");
  for (const permission of ["EXERCISE", "HEART_RATE", "DISTANCE", "SLEEP", "WEIGHT", "RESTING_HEART_RATE", "STEPS"]) {
    assert.ok(manifest.includes(`android.permission.health.READ_${permission}"`), permission);
  }
  assert.doesNotMatch(manifest, /android\.permission\.health\.WRITE_/);
  assert.match(manifest, /androidx\.health\.ACTION_SHOW_PERMISSIONS_RATIONALE/);
  assert.match(manifest, /android\.intent\.action\.VIEW_PERMISSION_USAGE/);
  assert.match(manifest, /<package android:name="com\.google\.android\.apps\.healthdata" \/>/);
  assert.match(read("../android/variables.gradle"), /minSdkVersion = 26/);
});
