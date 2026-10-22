// One id per sign-in, shared by the browser's tabs: a fresh sign-in starts a
// new one and signing out ends it, while restoring a session (reload, new tab,
// token refresh) keeps it. Lets "until next login" UI, such as the admin setup
// checklist, tell a new login from a page reload without a server session id.
const KEY = "palee:login-session";

function newId() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/** Storage can be unavailable (private mode, blocked site data); never throw. */
export function startLoginSession() {
  const id = newId();
  try {
    window.localStorage.setItem(KEY, id);
  } catch {}
  return id;
}

export function endLoginSession() {
  try {
    window.localStorage.removeItem(KEY);
  } catch {}
}

/** The current login's id; a session restored without one gets one now. */
export function currentLoginSession() {
  try {
    return window.localStorage.getItem(KEY) ?? startLoginSession();
  } catch {
    return null;
  }
}
