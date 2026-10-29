// ADR-256: opening the payment provider's checkout page (ADR-246) inside
// and outside the store apps.
//
// Everything Palee sells in the apps is a physical service or good of the
// box, which both stores require to be paid outside their own billing
// (Apple 3.1.3(e), Google Play Payments policy). The provider's page opens:
//   - on the web: in the same tab (the provider redirects back to /pay/return);
//   - in the apps: in the in-app browser (SFSafariViewController on iOS,
//     Custom Tabs on Android), never in the app's own web view, so the card
//     is typed on the provider's page with the browser's address bar and
//     password manager, and the app never sees it.
// The provider then redirects to https://<host>/pay/return, a universal link
// / App Link that brings the app back (deep-links.ts). If the payer closes
// the browser instead, the app still opens /pay/return for that payment, so
// it always asks the API what happened.
import { checkoutClosedPath } from "./deep-links";
import { nativePlatform, type NativePlatform } from "./index";

export type CheckoutMode = "in_app_browser" | "same_window";

export function checkoutMode(platform: NativePlatform | null): CheckoutMode {
  return platform ? "in_app_browser" : "same_window";
}

/** The provider's checkout URL if it is safe to open (https only), otherwise null. */
export function safeCheckoutUrl(url: unknown): string | null {
  if (typeof url !== "string") return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && !parsed.username && !parsed.password ? parsed.toString() : null;
  } catch {
    return null;
  }
}

/**
 * Remembers which payment the in-app browser is showing, so that closing it
 * without a redirect still leads to that payment's return page, once.
 */
export function createCheckoutTracker() {
  let pending: string | null = null;
  return {
    opened(paymentId: string) {
      pending = paymentId;
    },
    /** The provider redirected back: nothing more to do when the browser closes. */
    returned() {
      const had = pending !== null;
      pending = null;
      return had;
    },
    /** The browser closed: the page to show, or null when the return already came. */
    closed(): string | null {
      if (!pending) return null;
      const path = checkoutClosedPath(pending);
      pending = null;
      return path;
    },
    get pending() {
      return pending;
    },
  };
}

type Listener = { remove: () => Promise<void> };

type BrowserPlugin = {
  open(options: { url: string; presentationStyle?: "fullscreen" | "popover" }): Promise<void>;
  close(): Promise<void>;
  addListener(event: "browserFinished", callback: () => void): Promise<Listener>;
};

const tracker = createCheckoutTracker();
let finishedListener: Listener | null = null;

async function browser(): Promise<BrowserPlugin> {
  // The Browser plugin ships in the native projects (apps/mobile); the web
  // reaches it through the bridge, so it needs no extra package.
  const { registerPlugin } = await import("@capacitor/core");
  return registerPlugin<BrowserPlugin>("Browser");
}

/**
 * Opens the provider's checkout page for one payment. `navigate` shows an
 * in-app page (the router's push) when the payer closes the in-app browser
 * without being sent back.
 */
export async function openCheckout(url: string, { paymentId, navigate }: { paymentId: string; navigate: (path: string) => void }) {
  const safe = safeCheckoutUrl(url);
  if (!safe) throw new Error("unsafe_checkout_url");

  if (checkoutMode(nativePlatform()) === "same_window") {
    window.location.assign(safe);
    return;
  }

  const plugin = await browser();
  await finishedListener?.remove();
  finishedListener = await plugin.addListener("browserFinished", () => {
    const path = tracker.closed();
    if (path) navigate(path);
  });
  tracker.opened(paymentId);
  await plugin.open({ url: safe, presentationStyle: "fullscreen" });
}

/** Called when /pay/return opened the app: closes the in-app browser if it is still showing. */
export async function finishCheckout() {
  if (!tracker.returned()) return;
  try {
    // iOS only; on Android the app simply comes back in front of Custom Tabs.
    if (nativePlatform() === "ios") await (await browser()).close();
  } catch {
    // Already closed.
  }
}
