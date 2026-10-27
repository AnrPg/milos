/**
 * What a member pasted into Εγώ › Τα box μου › «Πρόσκληση ή join link»: a
 * gym's join link (`…/join/<slug>`), an invitation link (`…?token=<code>`),
 * or a bare invitation code.
 */
export type JoinInput = { kind: "join"; slug: string } | { kind: "invite"; token: string } | null;

export function parseJoinInput(raw: string): JoinInput {
  const text = raw.trim();
  if (!text) return null;

  const url = toUrl(text);
  if (url) {
    const join = url.pathname.match(/\/join\/([^/]+)\/?$/);
    if (join) return { kind: "join", slug: decodeURIComponent(join[1]) };
    // ADR-209: emailed links keep the token in the fragment (`/invite#token=…`).
    const token = (url.searchParams.get("token") ?? new URLSearchParams(url.hash.replace(/^#/, "")).get("token"))?.trim();
    return token ? { kind: "invite", token } : null;
  }

  if (/^\/?join\/[^/\s]+\/?$/.test(text)) return { kind: "join", slug: decodeURIComponent(text.replace(/^\/?join\//, "").replace(/\/$/, "")) };
  return /\s/.test(text) ? null : { kind: "invite", token: text };
}

function toUrl(text: string): URL | null {
  if (!/^https?:\/\//i.test(text) && !/^[\w.-]+\.[a-z]{2,}\//i.test(text)) return null;
  try {
    return new URL(/^https?:\/\//i.test(text) ? text : `https://${text}`);
  } catch {
    return null;
  }
}
