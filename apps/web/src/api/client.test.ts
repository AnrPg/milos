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

  it("replaces a remembered retired slug with the canonical slug the API names (ADR-122)", async () => {
    window.history.replaceState(null, "", "/admin/users");
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, "old-gym");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "x-organization-canonical-slug": "new-gym" },
      }),
    );

    await apiRequest<{ ok: boolean }>("/admin/users", { token: "token" });
    expect(fetchMock).toHaveBeenLastCalledWith("/api/org/old-gym/admin/users", expect.anything());
    expect(window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY)).toBe("new-gym");

    await apiRequest<{ ok: boolean }>("/admin/users", { token: "token" });
    expect(fetchMock).toHaveBeenLastCalledWith("/api/org/new-gym/admin/users", expect.anything());
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

  it("hydrates the selected organization before tenant admin requests without a path slug", async () => {
    window.history.replaceState(null, "", "/admin/workouts/new");
    const fetchMock = vi.spyOn(window, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify([
            { role: "admin", organization: { slug: "palee-method" } },
          ]),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(JSON.stringify({ draft: { id: "draft-1" } }), { status: 201 }));

    await apiRequest<{ draft: { id: string } }>("/admin/workouts", {
      method: "POST",
      token: "token",
    });

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      "/api/memberships",
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer token" }),
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "/api/org/palee-method/admin/workouts",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({ "X-Organization-Slug": "palee-method" }),
      }),
    );
    expect(window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY)).toBe("palee-method");
  });

  it("hydrates the selected organization before tenant member finance requests", async () => {
    window.history.replaceState(null, "", "/admin/workouts/new");
    const fetchMock = vi.spyOn(window, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify([
            { role: "member", organization: { slug: "palee-method" } },
          ]),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(JSON.stringify({ credit_balance: 0 }), { status: 200 }));

    await apiRequest<{ credit_balance: number }>("/me/finance", { token: "token" });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/memberships", expect.anything());
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "/api/org/palee-method/me/finance",
      expect.anything(),
    );
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

  it("does not double-prefix an explicitly tenant-scoped path", async () => {
    window.history.replaceState(null, "", "/org/atlas-gym/admin");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/org/atlas-gym/me/threads/unread-count", { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/org/atlas-gym/me/threads/unread-count",
      expect.anything(),
    );
  });

  it("sends account-scoped paths as they are, without a gym (ADR-162)", async () => {
    window.history.replaceState(null, "", "/org/atlas-gym/journal");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>("/me/progress?range=12w", { token: "token", scope: "account" });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/me/progress?range=12w",
      expect.objectContaining({
        headers: expect.not.objectContaining({ "X-Organization-Slug": expect.anything() }),
      }),
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
    [
      "/me/workouts/w-1/injury-warnings?surface=pre_start",
      "/api/org/atlas-gym/me/workouts/w-1/injury-warnings?surface=pre_start",
    ],
    ["/locations", "/api/org/atlas-gym/locations"],
    ["/check-ins", "/api/org/atlas-gym/check-ins"],
    ["/my-workouts?start_date=2026-08-08", "/api/org/atlas-gym/my-workouts?start_date=2026-08-08"],
    ["/workouts/workout-1", "/api/org/atlas-gym/workouts/workout-1"],
    ["/workouts/workout-1/scales", "/api/org/atlas-gym/workouts/workout-1/scales"],
    ["/me/finance", "/api/org/atlas-gym/me/finance"],
    ["/me/entitlement", "/api/org/atlas-gym/me/entitlement"],
    ["/me/documents/t-1/sign", "/api/org/atlas-gym/me/documents/t-1/sign"],
    ["/challenges/c-1/leaderboard", "/api/org/atlas-gym/challenges/c-1/leaderboard"],
    ["/challenges/c-1/opt_in", "/api/org/atlas-gym/challenges/c-1/opt_in"],
    ["/landing/leaderboard-opt-in", "/api/org/atlas-gym/landing/leaderboard-opt-in"],
  ])("scopes org-only member path %s", async (path, expectedPath) => {
    window.history.replaceState(null, "", "/org/atlas-gym/schedule");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>(path, { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(expectedPath, expect.anything());
  });

  // ADR-193: people search, Buddies and privacy live in the personal session.
  it.each([
    "/people-search?q=ma",
    "/me/buddies-list?q=ma",
    "/me/social/privacy",
    "/me/followers",
    "/me/following?type=user",
  ])("keeps the account-scoped social path %s outside the gym", async (path) => {
    window.history.replaceState(null, "", "/org/atlas-gym/schedule");
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );

    await apiRequest<{ ok: boolean }>(path, { token: "token" });

    expect(fetchMock).toHaveBeenCalledWith(`/api${path}`, expect.anything());
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
