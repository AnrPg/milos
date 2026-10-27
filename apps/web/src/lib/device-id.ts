// ADR-208: a long-lived random id for this browser (and the native app, which
// is the same web app), sent when signing in so the API can tell a sign-in
// from a device never seen before and email the person. The API keeps only a
// hash of it and also sets it as an httpOnly cookie; this copy keeps the
// device recognised when cookies are cleared. Never personal data.
export const DEVICE_ID_KEY = "palee:device-id";
export const DEVICE_ID_HEADER = "x-palee-device-id";

const VALID = /^[A-Za-z0-9_-]{16,128}$/;

function randomId() {
  const bytes = new Uint8Array(24);
  if (typeof crypto !== "undefined" && "getRandomValues" in crypto) {
    crypto.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index += 1) bytes[index] = Math.floor(Math.random() * 256);
  }
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** This device's id, created on first use; null when storage is unavailable (the cookie still works). */
export function deviceId(): string | null {
  if (typeof window === "undefined") return null;
  try {
    const stored = window.localStorage.getItem(DEVICE_ID_KEY);
    if (stored && VALID.test(stored)) return stored;
    const created = randomId();
    window.localStorage.setItem(DEVICE_ID_KEY, created);
    return created;
  } catch {
    return null;
  }
}

/** The header to send with a sign-in or sign-up request (empty when there is no id). */
export function deviceHeaders(): Record<string, string> {
  const id = deviceId();
  return id ? { [DEVICE_ID_HEADER]: id } : {};
}
