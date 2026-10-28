/**
 * What a member pasted into Εγώ › Τα box μου › «Πρόσκληση ή join link»: a
 * gym's join link (`…/join/<slug>`, or the athlete link
 * `…/join/<slug>/athlete/<key>`, ADR-216), an invitation link
 * (`…?token=<code>`), or a bare invitation code.
 */
export type JoinInput =
  | { kind: "join"; slug: string; athleteKey?: string }
  | { kind: "invite"; token: string }
  | null;

const JOIN_PATH = /(?:^|\/)join\/([^/\s]+)(?:\/athlete\/([^/\s]+))?\/?$/;

function joinFromPath(path: string): JoinInput {
  const match = path.match(JOIN_PATH);
  if (!match) return null;
  const slug = decodeURIComponent(match[1]);
  return match[2] ? { kind: "join", slug, athleteKey: decodeURIComponent(match[2]) } : { kind: "join", slug };
}

export function parseJoinInput(raw: string): JoinInput {
  const text = raw.trim();
  if (!text) return null;

  const url = toUrl(text);
  if (url) {
    const join = joinFromPath(url.pathname);
    if (join) return join;
    // ADR-209: emailed links keep the token in the fragment (`/invite#token=…`).
    const token = (url.searchParams.get("token") ?? new URLSearchParams(url.hash.replace(/^#/, "")).get("token"))?.trim();
    return token ? { kind: "invite", token } : null;
  }

  const join = /^\/?join\//.test(text) ? joinFromPath(text) : null;
  if (join) return join;
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
