import { describe, expect, it } from "vitest";

import { APP_LINK_PATH_PREFIXES, appleAppSiteAssociation, assetLinks } from "./app-links";
import { checkoutClosedPath, parsePaymentReturn, paymentReturnBody, routeDeepLink } from "./deep-links";

const origin = "https://palee.example";
const paymentId = "0b6f3c1e-2d4a-4f7b-9a8c-1e2f3a4b5c6d";

describe("deep links", () => {
  it("the payment return is one of the app links, in both stores' files", () => {
    expect(APP_LINK_PATH_PREFIXES).toContain("/pay/return");
    expect(appleAppSiteAssociation({ APPLE_TEAM_ID: "ABCDE12345" })?.applinks.details[0].components).toContainEqual({
      "/": "/pay/return*",
    });
    expect(assetLinks({ ANDROID_SHA256_CERT_FINGERPRINTS: Array.from({ length: 32 }, () => "0F").join(":") })?.[0].target.package_name).toBe("app.palee.member");
  });

  it("routes the provider's return to the payment return with the payment id", () => {
    const link = routeDeepLink(`${origin}/pay/return?payment=${paymentId}`, origin);
    expect(link).toEqual({
      kind: "payment_return",
      path: `/pay/return?payment=${paymentId}`,
      payment: { payment_id: paymentId, cancelled: false },
    });
  });

  it("reads the cancel url and Viva's order code and transaction id", () => {
    const link = routeDeepLink(`${origin}/pay/return/?payment=${paymentId.toUpperCase()}&cancelled=1&s=7290123456789012&t=a1b2-c3d4&lang=el-GR`, origin);
    expect(link?.kind).toBe("payment_return");
    if (link?.kind !== "payment_return") return;
    expect(link.payment).toEqual({
      payment_id: paymentId,
      provider_ref: "7290123456789012",
      transaction_id: "a1b2-c3d4",
      cancelled: true,
    });
  });

  it("drops values that are not a payment id or a provider reference", () => {
    expect(parsePaymentReturn("payment=../../admin&s=<script>&t=" + "x".repeat(201))).toEqual({ cancelled: false });
    expect(paymentReturnBody(parsePaymentReturn(""))).toBeNull();
  });

  it("builds the body the API's return endpoint takes", () => {
    expect(paymentReturnBody({ payment_id: paymentId, transaction_id: "t-1", cancelled: false })).toEqual({
      payment_id: paymentId,
      transaction_id: "t-1",
    });
    expect(paymentReturnBody({ provider_ref: "123", cancelled: true })).toEqual({ provider_ref: "123" });
  });

  it("opens join and other share links as pages", () => {
    expect(routeDeepLink(`${origin}/join/box-1?code=abc`, origin)).toEqual({ kind: "page", path: "/join/box-1?code=abc" });
    expect(routeDeepLink(`${origin}/pay/returns`, origin)).toEqual({ kind: "page", path: "/pay/returns" });
  });

  it("ignores links to other hosts and other schemes", () => {
    expect(routeDeepLink(`https://evil.example/pay/return?payment=${paymentId}`, origin)).toBeNull();
    expect(routeDeepLink("palee://pay/return", origin)).toBeNull();
    expect(routeDeepLink("not a url", origin)).toBeNull();
  });

  it("names the page shown when the payer closes the checkout", () => {
    expect(checkoutClosedPath(paymentId)).toBe(`/pay/return?payment=${paymentId}&closed=1`);
  });
});
