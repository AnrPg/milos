import { describe, expect, it } from "vitest";

import { buildMailto, relativeTime, resetLinkFor } from "./reset-email";

describe("resetLinkFor", () => {
  it("puts the token in the fragment of the reset page", () => {
    expect(resetLinkFor("https://app.palee.gr", "abc_DEF-123")).toBe("https://app.palee.gr/reset-password#token=abc_DEF-123");
    expect(resetLinkFor("https://app.palee.gr/", "t")).toBe("https://app.palee.gr/reset-password#token=t");
  });
});

describe("buildMailto", () => {
  it("prefills recipient, subject and body, percent-encoded", () => {
    const url = buildMailto({
      to: "maria+box@example.com",
      subject: "Your reset link & more",
      body: "Hi Μαρία,\n\nOpen https://app.palee.gr/reset-password#token=a?b=c\n\nThanks",
    });
    expect(url.startsWith("mailto:maria%2Bbox@example.com?subject=")).toBe(true);
    expect(url).toContain("subject=Your%20reset%20link%20%26%20more");
    expect(url).not.toContain("+");
    expect(url).toContain("%0D%0A%0D%0AOpen%20https%3A%2F%2Fapp.palee.gr%2Freset-password%23token%3Da%3Fb%3Dc");

    const parsed = new URL(url);
    expect(parsed.protocol).toBe("mailto:");
    expect(decodeURIComponent(parsed.pathname)).toBe("maria+box@example.com");
    expect(parsed.searchParams.get("body")).toBe(
      "Hi Μαρία,\r\n\r\nOpen https://app.palee.gr/reset-password#token=a?b=c\r\n\r\nThanks",
    );
    expect(parsed.searchParams.get("subject")).toBe("Your reset link & more");
  });

  it("normalizes every kind of line break to CRLF", () => {
    expect(buildMailto({ to: "a@b.c", subject: "s", body: "1\r\n2\r3\n4" })).toBe(
      "mailto:a@b.c?subject=s&body=1%0D%0A2%0D%0A3%0D%0A4",
    );
  });
});

describe("relativeTime", () => {
  const now = Date.parse("2026-10-23T12:00:00Z");

  it("names the nearest whole unit", () => {
    expect(relativeTime("2026-10-23T11:55:00Z", now, "en")).toBe("5 minutes ago");
    expect(relativeTime("2026-10-24T11:00:00Z", now, "en")).toBe("in 23 hours");
    expect(relativeTime("2026-10-21T12:00:00Z", now, "en")).toBe("2 days ago");
    expect(relativeTime("2026-10-23T11:59:40Z", now, "en")).toBe("this minute");
  });

  it("returns nothing for an unreadable time", () => {
    expect(relativeTime("nope", now, "en")).toBe("");
  });
});
