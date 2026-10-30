// ADR-277: the platform can replace its Web Push key pair. A browser
// subscription made with the old public key can never be delivered again, so
// the app compares the key a subscription was made with to the current one.

export function base64UrlToBytes(value: string): Uint8Array<ArrayBuffer> {
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  const raw = atob((value + padding).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

/**
 * True when `subscription` was made with `publicKey` (base64url). A browser
 * that does not report the key it subscribed with gets the benefit of the doubt.
 */
export function subscriptionUsesKey(
  subscription: { options?: { applicationServerKey?: ArrayBuffer | null } | null },
  publicKey: string,
): boolean {
  const used = subscription.options?.applicationServerKey;
  if (!used) return true;
  const current = base64UrlToBytes(publicKey);
  const bytes = new Uint8Array(used);
  return bytes.length === current.length && bytes.every((byte, index) => byte === current[index]);
}
