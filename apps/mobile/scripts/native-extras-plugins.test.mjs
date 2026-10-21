// ADR-173: the widget, geofence and NFC plugins can't be compiled here, so
// these checks keep their wiring honest: the same methods on iOS, Android and
// the web wrappers, every native file reachable by the app build, and the
// manifest/entitlements each feature needs.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { androidNdefFilter } from "./configure.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const kotlin = (name) => read(`../android/app/src/main/java/app/milos/member/${name}`);

const PLUGINS = [
  { js: "MilosWidgets", swift: "MilosWidgetsPlugin", kt: "MilosWidgetsPlugin", web: "widgets.ts", methods: ["setSession", "clear"] },
  {
    js: "MilosGeofence",
    swift: "MilosGeofencePlugin",
    kt: "MilosGeofencePlugin",
    web: "geofence.ts",
    methods: ["checkPermissions", "requestPermissions", "setRegions", "clear"],
  },
  { js: "MilosNfc", swift: "MilosNfcPlugin", kt: "MilosNfcPlugin", web: "nfc.ts", methods: ["isAvailable", "write"] },
];

test("iOS and Android expose the methods the web wrappers call", () => {
  for (const plugin of PLUGINS) {
    const swift = read(`../ios/App/App/${plugin.swift}.swift`);
    const kt = kotlin(`${plugin.kt}.kt`);
    const web = read(`../../web/src/lib/platform/${plugin.web}`);
    assert.match(swift, new RegExp(`jsName = "${plugin.js}"`));
    assert.match(kt, new RegExp(`@CapacitorPlugin\\(\\s*name = "${plugin.js}"`));
    assert.match(web, new RegExp(`registerPlugin<[^>]*>\\("${plugin.js}"\\)`));
    for (const method of plugin.methods) {
      assert.match(swift, new RegExp(`CAPPluginMethod\\(name: "${method}"`), `swift ${plugin.js}.${method}`);
      assert.match(kt, new RegExp(`fun ${method}\\(call: PluginCall\\)`), `kotlin ${plugin.js}.${method}`);
      assert.match(web, new RegExp(`\\b${method}\\(`), `web ${plugin.js}.${method}`);
    }
  }
});

test("the iOS plugins are compiled and registered by the app's controller", () => {
  const project = read("../ios/App/App.xcodeproj/project.pbxproj");
  const controller = read("../ios/App/App/MilosBridgeViewController.swift");
  for (const { swift } of PLUGINS) {
    assert.match(project, new RegExp(`/\\* ${swift}.swift in Sources \\*/,`), `${swift} in the Sources phase`);
    assert.match(project, new RegExp(`isa = PBXFileReference;[^}]*path = ${swift}.swift;`), `${swift} file reference`);
    assert.match(controller, new RegExp(`registerPluginInstance\\(${swift}\\(\\)\\)`));
  }
  // The scene builds its window in code, so it must use the app's controller.
  assert.match(read("../ios/App/App/SceneDelegate.swift"), /rootViewController = MilosBridgeViewController\(\)/);
  assert.match(read("../ios/App/App/AppDelegate.swift"), /MilosGeofenceMonitor\.shared\.start\(\)/);
  const plist = read("../ios/App/App/Info.plist");
  for (const key of ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NFCReaderUsageDescription"]) {
    assert.match(plist, new RegExp(`<key>${key}</key>`), key);
  }
  const entitlements = read("../ios/App/App/App.entitlements");
  assert.match(entitlements, /group\.app\.milos\.member/);
  assert.match(entitlements, /com\.apple\.developer\.nfc\.readersession\.formats/);
  assert.match(read("../ios/App/MilosWidgets/MilosWidgets.entitlements"), /group\.app\.milos\.member/);
  assert.match(read("../ios/App/App/MilosWidgetsPlugin.swift"), /"group\.app\.milos\.member"/);
});

test("the Android plugins, widgets and receivers are registered", () => {
  const activity = kotlin("MainActivity.java");
  for (const { kt } of PLUGINS) assert.match(activity, new RegExp(`registerPlugin\\(${kt}\\.class\\)`));
  const manifest = read("../android/app/src/main/AndroidManifest.xml");
  for (const receiver of ["WaterWidgetProvider", "TodayWidgetProvider", "CheckInWidgetProvider", "MilosGeofenceReceiver", "MilosGeofenceBootReceiver"]) {
    assert.match(manifest, new RegExp(`android:name="\\.${receiver}"`), receiver);
  }
  for (const permission of ["ACCESS_FINE_LOCATION", "ACCESS_BACKGROUND_LOCATION", "POST_NOTIFICATIONS", "RECEIVE_BOOT_COMPLETED", "NFC"]) {
    assert.ok(manifest.includes(`android.permission.${permission}"`), permission);
  }
  assert.match(manifest, /android\.nfc\.action\.NDEF_DISCOVERED/);
  assert.match(read("../android/app/build.gradle"), /play-services-location/);
  for (const name of ["water", "today", "checkin"]) {
    assert.match(read(`../android/app/src/main/res/xml/milos_widget_${name}.xml`), new RegExp(`@layout/widget_${name}`));
  }
  assert.match(kotlin("MilosWidgetProviders.kt"), /"app\.milos\.member\.widget\.ADD_WATER"/);
});

test("widgets and the web agree on the snapshot and tap paths", () => {
  const web = read("../../web/src/lib/platform/widgets.ts");
  for (const key of ["water", "today", "checkIn"]) assert.match(web, new RegExp(`${key}: "/`));
  const swiftWidgets = read("../ios/App/MilosWidgets/MilosWidgets.swift");
  for (const source of [swiftWidgets, kotlin("MilosWidgetData.kt")]) {
    assert.match(source, /\/api\/widget\/snapshot\?timezone=/);
    assert.match(source, /\/api\/widget\/water/);
  }
});

test("NFC tag links open the app on Android", () => {
  const filter = androidNdefFilter("milos.test");
  assert.match(filter, /NDEF_DISCOVERED/);
  assert.match(filter, /android:host="milos\.test"/);
  assert.match(filter, /android:pathPrefix="\/c\/"/);
});
