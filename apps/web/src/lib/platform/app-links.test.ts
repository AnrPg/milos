import { describe, expect, it } from "vitest";

import { APP_LINK_PATH_PREFIXES, appleAppSiteAssociation, assetLinks, inAppPath, notificationPath } from "./app-links";

const APP_KEY = Array.from({ length: 32 }, (_, index) => (index * 7).toString(16).padStart(2, "0").slice(-2).toUpperCase()).join(":");
const UPLOAD_KEY = Array.from({ length: 32 }, () => "AB").join(":");

describe("app links", () => {
  it("covers the share links: QR check-in, join, box page and the other invites", () => {
    for (const prefix of ["/c/", "/join/", "/b/", "/r/", "/events/", "/trials/", "/buddy/"]) {
      expect(APP_LINK_PATH_PREFIXES).toContain(prefix);
    }
  });

  it("serves no apple-app-site-association until the team id is set", () => {
    expect(appleAppSiteAssociation({})).toBeNull();
  });

  it("builds the apple-app-site-association from the team and bundle ids", () => {
    const document = appleAppSiteAssociation({ APPLE_TEAM_ID: "ABCDE12345" });
    expect(document?.applinks.details[0].appIDs).toEqual(["ABCDE12345.app.palee.member"]);
    expect(document?.applinks.details[0].components).toContainEqual({ "/": "/c/*" });
    expect(document?.webcredentials.apps).toEqual(["ABCDE12345.app.palee.member"]);
    expect(
      appleAppSiteAssociation({ APPLE_TEAM_ID: "ABCDE12345", IOS_BUNDLE_ID: "a.b, a.b.dev" })?.applinks.details[0].appIDs,
    ).toEqual(["ABCDE12345.a.b", "ABCDE12345.a.b.dev"]);
  });

  it("ignores a team id that is not one (a placeholder from .env.example)", () => {
    expect(appleAppSiteAssociation({ APPLE_TEAM_ID: "YOUR_TEAM_ID" })).toBeNull();
    expect(appleAppSiteAssociation({ APPLE_TEAM_ID: "T" })).toBeNull();
    expect(appleAppSiteAssociation({ APPLE_TEAM_ID: " abcde12345 " })?.applinks.details[0].appIDs).toEqual(["ABCDE12345.app.palee.member"]);
  });

  it("serves no assetlinks.json until a fingerprint is set, then one statement for the package", () => {
    expect(assetLinks({})).toBeNull();
    const statements = assetLinks({ ANDROID_SHA256_CERT_FINGERPRINTS: `${APP_KEY.toLowerCase()}, ${UPLOAD_KEY}` });
    expect(statements).toEqual([
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: { namespace: "android_app", package_name: "app.palee.member", sha256_cert_fingerprints: [APP_KEY, UPLOAD_KEY] },
      },
    ]);
  });

  it("ignores fingerprints that are not a SHA-256 (placeholders, SHA-1)", () => {
    expect(assetLinks({ ANDROID_SHA256_CERT_FINGERPRINTS: "AA:BB:CC:...:FF,11:22:33:...:99" })).toBeNull();
    expect(assetLinks({ ANDROID_SHA256_CERT_FINGERPRINTS: "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD" })).toBeNull();
    expect(assetLinks({ ANDROID_SHA256_CERT_FINGERPRINTS: `nope,${APP_KEY}` })?.[0].target.sha256_cert_fingerprints).toEqual([APP_KEY]);
  });

  it("opens only links to this web app's own host", () => {
    const origin = "https://palee.example";
    expect(inAppPath("https://palee.example/c/loc-1/abc?x=1#y", origin)).toBe("/c/loc-1/abc?x=1#y");
    expect(inAppPath("https://evil.example/c/loc-1/abc", origin)).toBeNull();
    expect(inAppPath("javascript:alert(1)", origin)).toBeNull();
    expect(inAppPath("not a url", origin)).toBeNull();
  });

  it("turns a notification link into an in-app path", () => {
    const origin = "https://palee.example";
    expect(notificationPath("/org/box/journal", origin)).toBe("/org/box/journal");
    expect(notificationPath("//evil.example/x", origin)).toBeNull();
    expect(notificationPath("https://palee.example/me", origin)).toBe("/me");
    expect(notificationPath(undefined, origin)).toBeNull();
  });
});
