import { describe, expect, it } from "vitest";

import { base64UrlToBytes, subscriptionUsesKey } from "@/lib/vapid-key-match";

const key = "BEZqb6JPO5byqDXJjxHUS7sDTjYsweyxtQqIj-bc4BLDgd-x1Gvjii4kImItGk6p2EpmM0s2a8M-4o_ZsFeDu_g";
const other = "BPa1Hn0a3XrLp9mS2y8nM6kq4yZJcwZr2qkU0hB5tR7WlqFz1oE8uGx2v5d9KJmHq3aZ4XcV0tN7bY6iP1sR8wE";

const madeWith = (publicKey: string | null) => ({
  options: { applicationServerKey: publicKey ? base64UrlToBytes(publicKey).buffer as ArrayBuffer : null },
});

describe("subscriptionUsesKey (ADR-275)", () => {
  it("matches a subscription made with the current key", () => {
    expect(subscriptionUsesKey(madeWith(key), key)).toBe(true);
  });

  it("spots a subscription made with keys the platform replaced", () => {
    expect(subscriptionUsesKey(madeWith(other), key)).toBe(false);
  });

  it("trusts a browser that does not say which key it used", () => {
    expect(subscriptionUsesKey(madeWith(null), key)).toBe(true);
    expect(subscriptionUsesKey({}, key)).toBe(true);
  });
});
