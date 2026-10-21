import { describe, expect, it } from "vitest";

import { APP_LINK_PATH_PREFIXES, appleAppSiteAssociation, assetLinks, inAppPath, notificationPath } from "./app-links";

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
    expect(document?.applinks.details[0].appIDs).toEqual(["ABCDE12345.app.milos.member"]);
    expect(document?.applinks.details[0].components).toContainEqual({ "/": "/c/*" });
    expect(document?.webcredentials.apps).toEqual(["ABCDE12345.app.milos.member"]);
    expect(
      appleAppSiteAssociation({ APPLE_TEAM_ID: "T", IOS_BUNDLE_ID: "a.b, a.b.dev" })?.applinks.details[0].appIDs,
    ).toEqual(["T.a.b", "T.a.b.dev"]);
  });

  it("serves no assetlinks.json until a fingerprint is set, then one statement for the package", () => {
    expect(assetLinks({})).toBeNull();
    const statements = assetLinks({ ANDROID_SHA256_CERT_FINGERPRINTS: "aa:bb, CC:DD" });
    expect(statements).toEqual([
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: { namespace: "android_app", package_name: "app.milos.member", sha256_cert_fingerprints: ["AA:BB", "CC:DD"] },
      },
    ]);
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
