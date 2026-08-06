import { afterEach, describe, expect, it, vi } from "vitest";

import { apiRequest, SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

describe("apiRequest tenant headers", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.clear();
    window.history.replaceState(null, "", "/");
  });

  it("uses the organization slug from /org paths", async () => {
    window.history.replaceState(null, "", "/org/atlas-gym/admin");
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, "stored-gym");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/admin/users", { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/org/atlas-gym/admin/users",
      expect.objectContaining({
        headers: expect.objectContaining({ "X-Organization-Slug": "atlas-gym" }),
      }),
    );
  });

  it("falls back to the selected organization for global admin pages", async () => {
    window.history.replaceState(null, "", "/admin/users");
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, "selected-gym");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/admin/users", { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/org/selected-gym/admin/users",
      expect.objectContaining({
        headers: expect.objectContaining({ "X-Organization-Slug": "selected-gym" }),
      }),
    );
  });

  it("falls back to the token membership when no selected organization is stored", async () => {
    window.history.replaceState(null, "", "/admin/users");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );
    const payload = window.btoa(JSON.stringify({
      memberships: [{ organization_slug: "token-gym" }],
    }));

    await apiRequest<{ ok: boolean }>("/admin/users", { token: `header.${payload}.signature` });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/org/token-gym/admin/users",
      expect.objectContaining({
        headers: expect.objectContaining({ "X-Organization-Slug": "token-gym" }),
      }),
    );
  });

  it("does not rewrite the path when no organization slug can be resolved", async () => {
    window.history.replaceState(null, "", "/admin/users");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/admin/users", { token: null });

    expect(fetchMock).toHaveBeenCalledWith("/api/admin/users", expect.anything());
  });

  it("scopes /me/search/users under the resolved organization", async () => {
    window.history.replaceState(null, "", "/org/atlas-gym/admin");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/me/search/users?q=abc", { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/org/atlas-gym/me/search/users?q=abc",
      expect.anything(),
    );
  });
});
