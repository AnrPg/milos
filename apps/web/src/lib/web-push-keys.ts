// ADR-049/216: a Web Push (VAPID) key pair is a P-256 key; the public half is
// sent raw and base64url-encoded to browsers, the private half is the JWK `d`.

function bytesToBase64Url(bytes: ArrayBuffer) {
  const raw = String.fromCharCode(...new Uint8Array(bytes));
  return window.btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export async function generateVapidKeyPair() {
  const pair = await window.crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const publicKey = await window.crypto.subtle.exportKey("raw", pair.publicKey);
  const privateKey = await window.crypto.subtle.exportKey("jwk", pair.privateKey);

  if (typeof privateKey.d !== "string") throw new Error("vapid_key_export_failed");

  return { publicKey: bytesToBase64Url(publicKey), privateKey: privateKey.d };
}

/** Push services want a `mailto:` or `https:` contact; a bare email gets `mailto:`. */
export function normalizePushContact(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed === "") return null;
  if (/^(mailto:|https:\/\/)/i.test(trimmed)) return trimmed;
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) return `mailto:${trimmed}`;
  return trimmed;
}
