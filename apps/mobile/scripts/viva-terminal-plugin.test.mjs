// ADR-249: the PaleeVivaTerminal plugin can't be compiled here, so these
// checks keep its wiring honest: the same methods on iOS, Android and the
// web wrapper, the same schemes and callback everywhere (and in the API's
// config), the URL schemes declared, and the native files reachable by the
// app build. URL building and callback parsing are unit-tested in
// apps/web/src/lib/platform/viva-terminal.test.ts.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

const swift = read("../ios/App/App/PaleeVivaTerminalPlugin.swift");
const kotlin = read("../android/app/src/main/java/app/palee/member/PaleeVivaTerminalPlugin.kt");
const web = read("../../web/src/lib/platform/viva-terminal.ts");
const apiConfig = read("../../api/config/config.exs");

const METHODS = ["isAvailable", "pay", "takePendingResult"];
const CALLBACK = "palee-terminal://result";
const SCHEMES = ["vivapayclient://pay/v1", "palee-sandbox-terminal://pay/v1"];

test("iOS and Android expose the methods the web wrapper calls", () => {
  for (const method of METHODS) {
    assert.match(swift, new RegExp(`CAPPluginMethod\\(name: "${method}"`), `swift ${method}`);
    assert.match(kotlin, new RegExp(`@PluginMethod\\s+fun ${method}\\(`), `kotlin ${method}`);
    assert.match(web, new RegExp(`\\b${method}\\(`), `web ${method}`);
  }
  assert.match(swift, /jsName = "PaleeVivaTerminal"/);
  assert.match(kotlin, /@CapacitorPlugin\(name = "PaleeVivaTerminal"\)/);
  assert.match(web, /registerPlugin<PaleeVivaTerminalPlugin>\("PaleeVivaTerminal"\)/);
  // Both platforms hand the answer to the web app as a `result` event.
  assert.match(swift, /notifyListeners\("result"/);
  assert.match(kotlin, /notifyListeners\("result"/);
});

test("the same allowed schemes and callback on every side", () => {
  for (const scheme of SCHEMES) {
    assert.ok(swift.includes(`"${scheme}"`), `swift ${scheme}`);
    assert.ok(kotlin.includes(`"${scheme}"`), `kotlin ${scheme}`);
    assert.ok(web.includes(`"${scheme}"`), `web ${scheme}`);
  }
  assert.ok(web.includes(`"${CALLBACK}"`));
  assert.ok(apiConfig.includes(`callback: "${CALLBACK}"`), "the API sends the same callback");
  assert.match(swift, /callbackScheme = "palee-terminal"/);
  assert.match(swift, /callbackHost = "result"/);
  assert.match(kotlin, /CALLBACK_SCHEME = "palee-terminal"/);
  assert.match(kotlin, /CALLBACK_HOST = "result"/);
  // Never an ISV secret built on the phone.
  for (const source of [swift, kotlin, web]) assert.doesNotMatch(source, /ISV_clientSecret/);
});

test("the iOS plugin is compiled, registered, and may open and receive the schemes", () => {
  const project = read("../ios/App/App.xcodeproj/project.pbxproj");
  assert.match(project, /\/\* PaleeVivaTerminalPlugin\.swift in Sources \*\/,/);
  assert.match(project, /isa = PBXFileReference;[^}]*path = PaleeVivaTerminalPlugin\.swift;/);
  assert.match(read("../ios/App/App/PaleeBridgeViewController.swift"), /registerPluginInstance\(PaleeVivaTerminalPlugin\(\)\)/);
  const plist = read("../ios/App/App/Info.plist");
  assert.match(plist, /<key>LSApplicationQueriesSchemes<\/key>\s*<array>\s*<string>vivapayclient<\/string>/);
  assert.match(plist, /<key>CFBundleURLSchemes<\/key>\s*<array>\s*<string>palee-terminal<\/string>/);
});

test("the Android plugin is registered, sees the terminal app and receives its answer", () => {
  assert.match(read("../android/app/src/main/java/app/palee/member/MainActivity.java"), /registerPlugin\(PaleeVivaTerminalPlugin\.class\)/);
  const manifest = read("../android/app/src/main/AndroidManifest.xml");
  assert.match(manifest, /<data android:scheme="palee-terminal" android:host="result" \/>/);
  assert.match(manifest, /<queries>[\s\S]*<data android:scheme="vivapayclient" \/>[\s\S]*<\/queries>/);
  // The answer reaches the running activity (onNewIntent), not a second one.
  assert.match(manifest, /android:name="\.MainActivity"[\s\S]*?android:launchMode="singleTask"/);
});
