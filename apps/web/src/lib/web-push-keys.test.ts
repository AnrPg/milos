import { describe, expect, it } from "vitest";

import { generateVapidKeyPair, normalizePushContact } from "./web-push-keys";

describe("normalizePushContact", () => {
  it("adds mailto: to a bare email and keeps mailto:/https: contacts", () => {
    expect(normalizePushContact(" alerts@palee.app ")).toBe("mailto:alerts@palee.app");
    expect(normalizePushContact("mailto:ops@palee.app")).toBe("mailto:ops@palee.app");
    expect(normalizePushContact("https://palee.app/contact")).toBe("https://palee.app/contact");
  });

  it("turns an empty contact into null", () => {
    expect(normalizePushContact("   ")).toBeNull();
  });
});

describe("generateVapidKeyPair", () => {
  it("makes a 65-byte uncompressed public key and a 32-byte private key, base64url", async () => {
    const pair = await generateVapidKeyPair();
    expect(pair.publicKey).toMatch(/^[A-Za-z0-9_-]{87}$/);
    expect(pair.privateKey).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});
