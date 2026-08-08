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

  it("scopes /me/reviews under the resolved organization", async () => {
    window.history.replaceState(null, "", "/org/atlas-gym/account");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/me/reviews", { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith("/api/org/atlas-gym/me/reviews", expect.anything());
  });

  it.each([
    ["/schedule?days=7", "/api/org/atlas-gym/schedule?days=7"],
    ["/bookings", "/api/org/atlas-gym/bookings"],
    ["/my-workouts?start_date=2026-08-08", "/api/org/atlas-gym/my-workouts?start_date=2026-08-08"],
    ["/workouts/workout-1", "/api/org/atlas-gym/workouts/workout-1"],
    ["/workouts/workout-1/scales", "/api/org/atlas-gym/workouts/workout-1/scales"],
    ["/me/finance", "/api/org/atlas-gym/me/finance"],
    ["/me/entitlement", "/api/org/atlas-gym/me/entitlement"],
  ])("scopes org-only member path %s", async (path, expectedPath) => {
    window.history.replaceState(null, "", "/org/atlas-gym/schedule");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>(path, { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(expectedPath, expect.anything());
  });

  it("keeps the execution timer endpoint on its user-scoped route", async () => {
    window.history.replaceState(null, "", "/org/atlas-gym/workouts/workout-1");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/workouts/workout-1/timer-sequence?source=self_selected", {
      token: "token",
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workouts/workout-1/timer-sequence?source=self_selected",
      expect.anything(),
    );
  });
});
