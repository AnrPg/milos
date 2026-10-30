import { describe, expect, it } from "vitest";

import { checkoutMode, createCheckoutTracker, safeCheckoutUrl } from "./checkout";

const paymentId = "0b6f3c1e-2d4a-4f7b-9a8c-1e2f3a4b5c6d";

describe("checkout", () => {
  it("opens the provider's page in the in-app browser inside the apps and in the same tab on the web", () => {
    expect(checkoutMode("ios")).toBe("in_app_browser");
    expect(checkoutMode("android")).toBe("in_app_browser");
    expect(checkoutMode(null)).toBe("same_window");
  });

  it("opens only https provider pages", () => {
    expect(safeCheckoutUrl("https://www.vivapayments.com/web/checkout?ref=123")).toBe("https://www.vivapayments.com/web/checkout?ref=123");
    expect(safeCheckoutUrl("https://checkout.stripe.com/c/pay/cs_test_1")).toBe("https://checkout.stripe.com/c/pay/cs_test_1");
    expect(safeCheckoutUrl("http://checkout.stripe.com/c/pay/cs_test_1")).toBeNull();
    expect(safeCheckoutUrl("javascript:alert(1)")).toBeNull();
    expect(safeCheckoutUrl("https://user:secret@checkout.stripe.com/")).toBeNull();
    expect(safeCheckoutUrl(undefined)).toBeNull();
  });

  it("shows the payment's return page when the payer closes the browser without coming back", () => {
    const tracker = createCheckoutTracker();
    tracker.opened(paymentId);
    expect(tracker.closed()).toBe(`/pay/return?payment=${paymentId}&closed=1`);
    expect(tracker.closed()).toBeNull();
  });

  it("does nothing more on close once the provider sent the payer back", () => {
    const tracker = createCheckoutTracker();
    tracker.opened(paymentId);
    expect(tracker.returned()).toBe(true);
    expect(tracker.closed()).toBeNull();
    expect(tracker.returned()).toBe(false);
  });
});
