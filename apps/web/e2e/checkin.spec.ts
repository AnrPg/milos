import { expect, test, type Page } from "./support/test";

// Redesign Phase 2 M7 (ADR-155, plan board 10): QR check-in. The door kiosk
// walking through its batch of codes, the phone landing after a door or
// poster scan (checked in with undo, picking a booking, a visitor offered a
// trial, the poster's limits), Box › Check-in with a rotating or a fixed code
// and Wallet, the desk scanner (through its test hook, no camera), the
// owner's mode switch that asks first, and Me › Connected devices. The API
// is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const inMinutes = (minutes: number) => new Date(Date.now() + minutes * 60_000).toISOString();

function personaFor(role: "member" | "admin", membershipRole: string) {
  const user = {
    id: role === "member" ? "member-1" : "owner-1",
    nickname: role === "member" ? "Maria" : "Apostolos",
    role,
    email: `${role}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: membershipRole, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = (role: string, capabilities: Record<string, unknown>) => ({
  role,
  roles: [role],
  capabilities,
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
});

async function common(page: Page, as: "member" | "admin") {
  const persona = as === "member" ? personaFor("member", "member") : personaFor("admin", "owner");
  const memberships = as === "member" ? [membership("member", {})] : [membership("owner", { manage_settings: true })];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
}

const box = { organization_id: "org-1", slug: "kypseli", name: "Box Kypseli", logo_url: null, primary_color: null };
const location = { id: "loc-1", name: "Kypseli" };
const booking = (id: string, name: string) => ({ id, name, scheduled_class_id: `class-${id}`, starts_at: inMinutes(10), duration_minutes: 60, kind: "member", location_id: "loc-1" });

test.describe("QR check-in", () => {
  test("the door kiosk walks through its batch and fetches the next one in time", async ({ page }) => {
    const start = Math.floor(Date.now() / 1000) * 1000;
    const iso = (offsetSeconds: number) => new Date(start + offsetSeconds * 1000).toISOString();
    let fetches = 0;
    await page.clock.install({ time: start });
    await common(page, "admin");
    // Batch k holds codes 2k…2k+3, 30 s apart: each fetch starts one minute later.
    await page.route("**/api/org/*/admin/check-in/door/loc-1", (route) => {
      const batch = fetches;
      fetches += 1;
      const codes = [0, 1, 2, 3].map((step) => {
        const index = batch * 2 + step;
        return {
          code: `D1code${index}`,
          deep_link: `http://127.0.0.1:18301/c/loc-1/D1code${index}`,
          shows_from: iso(index * 30),
          valid_until: iso(index * 30 + 60),
        };
      });
      return route.fulfill(
        json({
          code: codes[0].code,
          deep_link: codes[0].deep_link,
          codes,
          location,
          rotation_seconds: 30,
          server_time: iso(batch * 60),
          topic: "check_in:org-1",
          next_class: { id: "class-1", name: "WOD", starts_at: inMinutes(45), spots_remaining: 3 },
        }),
      );
    });

    await page.goto("/admin/check-in/door/loc-1");
    const qr = page.getByTestId("door-qr");
    await expect(qr).toHaveAttribute("data-value", "http://127.0.0.1:18301/c/loc-1/D1code0");
    await expect(page.getByRole("img", { name: "QR code for check-in at the door" })).toBeVisible();
    await expect(page.getByTestId("door-countdown")).toContainText("New code in 0:");
    await expect(page.getByText("WOD")).toBeVisible();
    await expect(page.getByText("3 spots")).toBeVisible();

    for (const index of [1, 2, 3, 4, 5]) {
      await page.clock.fastForward(30_000);
      await expect(qr).toHaveAttribute("data-value", `http://127.0.0.1:18301/c/loc-1/D1code${index}`);
    }
    // Code 4 only exists in a later batch: the kiosk fetched again before the first ran out.
    expect(fetches).toBeGreaterThanOrEqual(2);
    await expect(page.getByTestId("door-offline")).toBeHidden();
  });

  test.describe("scan landing", () => {
    async function scanStub(page: Page, answers: Array<(body: Record<string, unknown>) => unknown>) {
      const bodies: Array<Record<string, unknown>> = [];
      await page.route("**/api/check-in/scan", (route) => {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        bodies.push(body);
        const answer = answers[Math.min(bodies.length - 1, answers.length - 1)];
        return route.fulfill(json(answer(body)));
      });
      return bodies;
    }

    const checkedIn = (name: string) => ({
      outcome: "checked_in",
      box,
      location,
      membership: "member",
      check_in: { id: "ci-1", at: new Date().toISOString(), kind: "class", method: "door_qr", booking: booking("b-1", name) },
      package: { name: "10 visits", class_visits_left: 7, unlimited: false },
      undo_token: "undo-1",
      undo_until: inMinutes(1),
    });

    test("checked in, with a minute to undo", async ({ page }) => {
      await common(page, "member");
      const bodies = await scanStub(page, [() => checkedIn("WOD")]);
      const undos: string[] = [];
      await page.route("**/api/check-in/scan/*", (route) => {
        undos.push(route.request().method());
        return route.fulfill(json({ id: "ci-1", kind: "class", package: { name: "10 visits", class_visits_left: 8, unlimited: false } }));
      });

      await page.goto("/c/loc-1/D1doorcode");
      await expect(page.getByTestId("scan-checked-in")).toContainText("You're in! WOD");
      await expect(page.getByText("7 visits left")).toBeVisible();
      expect(bodies).toEqual([{ location_id: "loc-1", code: "D1doorcode" }]);

      await expect(page.getByTestId("scan-undo")).toContainText(/Undo \(\d+ s\)/);
      await page.getByTestId("scan-undo").click();
      await expect(page.getByTestId("scan-undone")).toHaveText("Check-in undone");
      await expect(page.getByText("8 visits left")).toBeVisible();
      expect(undos).toEqual(["DELETE"]);
    });

    test("more than one booking now: pick one", async ({ page }) => {
      await common(page, "member");
      const bodies = await scanStub(page, [
        () => ({ outcome: "choose", box, location, membership: "member", scan_token: "scan-1", choices: [booking("b-1", "WOD"), booking("b-2", "Gymnastics")] }),
        () => checkedIn("Gymnastics"),
      ]);

      await page.goto("/c/loc-1/D1doorcode");
      await expect(page.getByRole("heading", { name: "Which booking?" })).toBeVisible();
      await page.getByRole("button", { name: /Gymnastics/ }).click();
      await expect(page.getByTestId("scan-checked-in")).toContainText("You're in! Gymnastics");
      expect(bodies[1]).toEqual({ scan_token: "scan-1", booking_id: "b-2" });
    });

    test("a visitor sees the trial classes and books one from the sheet", async ({ page }) => {
      await common(page, "member");
      const slot = { id: "slot-1", name: "CrossFit Basics", starts_at: inMinutes(120), duration_minutes: 60, spots_remaining: 5, trial_seats: 2, location_id: "loc-1" };
      await scanStub(page, [
        () => ({
          outcome: "visitor",
          box,
          location,
          membership: "none",
          follow: "none",
          trial: { enabled: true, approval: "auto", blocked_reason: null, classes: [slot], mine: null },
        }),
      ]);
      const asks: unknown[] = [];
      await page.route("**/api/boxes/kypseli/trials", (route) => {
        asks.push(route.request().postDataJSON());
        return route.fulfill(
          json(
            {
              trial: {
                id: "trial-1",
                organization_id: "org-1",
                user_id: "member-1",
                scheduled_class_id: slot.id,
                booking_id: "booking-1",
                status: "booked",
                note: null,
                class_starts_at: slot.starts_at,
                inserted_at: new Date().toISOString(),
                class: { id: slot.id, name: slot.name, scheduled_at: slot.starts_at, duration_minutes: 60, location_id: "loc-1", class_type: null },
                box,
                location: { ...location, address: null, neighbourhood: null, city: null, latitude: null, longitude: null },
                bring_note: "Trainers and water.",
                follow_up: false,
              },
            },
            201,
          ),
        );
      });

      await page.goto("/c/loc-1/D1doorcode");
      await expect(page.getByTestId("scan-visitor")).toHaveText("You're not a member yet");
      await expect(page.getByText("Trial classes today and tomorrow")).toBeVisible();
      await page.getByRole("button", { name: "Book a trial" }).click();
      const sheet = page.getByRole("dialog", { name: "Trial class" });
      await expect(sheet.getByText("CrossFit Basics")).toBeVisible();
      await sheet.getByRole("button", { name: "Book the trial" }).click();
      await expect(page.getByRole("dialog", { name: "Booked" })).toBeVisible();
      expect(asks).toEqual([expect.objectContaining({ scheduled_class_id: slot.id, source: "qr_door" })]);
    });

    test("the poster only checks in to a booking starting now", async ({ page }) => {
      await common(page, "member");
      const bodies = await scanStub(page, [() => ({ outcome: "no_booking", box, location, membership: "member", package: null })]);

      await page.goto("/c/loc-1/p/P1postercode");
      await expect(page.getByText("The poster only checks in to a booking that's starting now.", { exact: false })).toBeVisible();
      await expect(page.getByRole("link", { name: "Open the schedule" })).toBeVisible();
      expect(bodies).toEqual([{ location_id: "loc-1", poster_code: "P1postercode" }]);
    });
  });

  test.describe("Box › Check-in", () => {
    test("a rotating code turns over and can't go in a Wallet", async ({ page }) => {
      await common(page, "member");
      let calls = 0;
      await page.route("**/api/org/kypseli/me/check-in/code", (route) => {
        calls += 1;
        return route.fulfill(
          json(
            calls === 1
              ? { code: "M1firstcode0", mode: "rotating", rotation_seconds: 30, seconds_until_rotation: 1, wallet_available: false }
              : { code: "M1secondcode", mode: "rotating", rotation_seconds: 30, seconds_until_rotation: 30, wallet_available: false },
          ),
        );
      });

      await page.goto("/box/check-in");
      const qr = page.getByTestId("member-qr");
      await expect(qr).toHaveAttribute("data-value", "M1firstcode0");
      await expect(qr).toHaveAttribute("data-value", "M1secondcode");
      await expect(page.getByTestId("member-countdown")).toContainText("Changes in 0:");
      await expect(page.getByText("The code keeps changing", { exact: false })).toBeVisible();
      await expect(page.getByTestId("wallet-card")).toBeHidden();
    });

    test("a fixed code goes in a Wallet and can be reset", async ({ page }) => {
      await common(page, "member");
      const walletAsks: unknown[] = [];
      await page.route("**/api/org/kypseli/me/check-in/code", (route) =>
        route.fulfill(json({ code: "S1fixedcode0", mode: "static", wallet_available: true })),
      );
      await page.route("**/api/org/kypseli/me/check-in/code/reset", (route) =>
        route.fulfill(json({ code: "S1freshcode0", mode: "static", wallet_available: true })),
      );
      await page.route("**/api/org/kypseli/me/wallet-passes", (route) => {
        walletAsks.push(route.request().postDataJSON());
        return route.fulfill(
          json({ pass: { id: "pass-1", active: true, platform: "apple", added_at: new Date().toISOString(), box: { name: "Box Kypseli" } }, download_url: null, save_url: null }, 201),
        );
      });

      await page.goto("/box/check-in");
      await expect(page.getByTestId("member-qr")).toHaveAttribute("data-value", "S1fixedcode0");
      await expect(page.getByTestId("member-countdown")).toBeHidden();
      const wallet = page.getByTestId("wallet-card");
      await wallet.getByRole("button", { name: "Apple Wallet" }).click();
      await expect(wallet.getByRole("status")).toHaveText("The card was added.");
      expect(walletAsks).toEqual([{ platform: "apple" }]);

      await page.getByTestId("member-reset").click();
      await page.getByRole("button", { name: "Yes, new code" }).click();
      await expect(page.getByTestId("member-qr")).toHaveAttribute("data-value", "S1freshcode0");
      await expect(page.getByText("You have a new code.")).toBeVisible();
    });
  });

  test.describe("desk", () => {
    const deskResult = (overrides: Record<string, unknown> = {}) => ({
      member: { id: "member-2", display_name: "Eleni Papadopoulou", nickname: "Eleni", avatar_url: null },
      method: "member_qr",
      decision: "class",
      bookings: [booking("b-1", "WOD")],
      can_auto_check_in: false,
      override_allowed: true,
      problems: ["package_expired"],
      warnings: ["payment_due"],
      package: { name: "10 visits", class_visits_left: 0, unlimited: false },
      checked_in: null,
      ...overrides,
    });

    async function desk(page: Page, scanAnswer: (body: Record<string, unknown>) => unknown) {
      await common(page, "admin");
      await page.addInitScript(() => {
        const target = window as unknown as { __paleeScannerSource: unknown; __paleeEmit: (text: string) => void };
        target.__paleeScannerSource = {
          start: (_video: HTMLVideoElement, onCode: (text: string) => void) => {
            target.__paleeEmit = onCode;
            return Promise.resolve(() => undefined);
          },
        };
      });
      const calls = { scans: [] as unknown[], checkIns: [] as unknown[], revokes: 0 };
      await page.route("**/api/org/*/admin/locations", (route) =>
        route.fulfill(json({ locations: [{ id: "loc-1", organization_id: "org-1", name: "Kypseli", archived_at: null, opening_hours: [], accessibility: [] }] })),
      );
      await page.route("**/api/org/*/admin/check-ins**", (route) => route.fulfill(json({ check_ins: [] })));
      await page.route("**/api/org/*/admin/check-in/visitors**", (route) =>
        route.fulfill(json({ visitors: [{ id: "scan-1", user_id: "visitor-1", display_name: "Nikos Visitor", scanned_at: inMinutes(-5), trial_offered: true, location_id: "loc-1", location_name: "Kypseli" }] })),
      );
      await page.route("**/api/org/*/admin/check-in/scan-member", (route) => {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        calls.scans.push(body);
        return route.fulfill(json(scanAnswer(body)));
      });
      await page.route("**/api/org/*/admin/check-in/members/member-2", (route) => {
        calls.checkIns.push(route.request().postDataJSON());
        return route.fulfill(json(deskResult({ checked_in: { kind: "class", booking: booking("b-1", "WOD"), override: true, method: "member_qr" } })));
      });
      await page.route("**/api/org/*/admin/check-in/members/member-2/code", (route) => {
        calls.revokes += 1;
        return route.fulfill(json({ revoked_codes: 1, revoked_passes: 1, user_id: "member-2" }));
      });
      await page.goto("/admin/check-in");
      await page.getByTestId("desk-scan-start").click();
      return calls;
    }

    const emit = (page: Page, text: string) => page.evaluate((value) => (window as unknown as { __paleeEmit: (text: string) => void }).__paleeEmit(value), text);

    test("a scan with a problem waits for staff; override, then revoke the code", async ({ page }) => {
      const calls = await desk(page, () => deskResult());
      await expect(page.getByTestId("desk-visitors")).toContainText("Nikos Visitor");

      await emit(page, "http://127.0.0.1:18301/c/loc-1/D1doorcode");
      await expect(page.getByText("That's the door's code.", { exact: false })).toBeVisible();

      await emit(page, "S1membercode");
      const result = page.getByTestId("desk-result");
      await expect(result).toContainText("Eleni Papadopoulou");
      await expect(result).toContainText("Package expired");
      await expect(result).toContainText("Payment due");
      await expect(page.getByTestId("desk-check-in")).toBeHidden();
      expect(calls.scans).toEqual([{ code: "S1membercode", auto: false }]);

      await page.getByTestId("desk-override").click();
      await expect(page.getByTestId("desk-checked-in")).toContainText("Checked in ✓ WOD");
      await expect(page.getByTestId("desk-checked-in")).toContainText("despite the problem");
      expect(calls.checkIns).toEqual([{ method: "member_qr", booking_id: "b-1", override: true }]);

      await result.getByRole("button", { name: "Revoke code" }).click();
      await result.getByRole("group").getByRole("button", { name: "Revoke code" }).click();
      await expect(page.getByText("The code was revoked along with 1 Wallet card.")).toBeVisible();
      expect(calls.revokes).toBe(1);
    });

    test("auto mode checks in a scan that's all fine", async ({ page }) => {
      const calls = await desk(page, () =>
        deskResult({ problems: [], warnings: [], can_auto_check_in: true, method: "wallet", checked_in: { kind: "class", booking: booking("b-1", "WOD"), method: "wallet" } }),
      );
      await page.getByRole("switch", { name: "Automatic check-in" }).check();
      await emit(page, "W1walletcode");
      await expect(page.getByTestId("desk-checked-in")).toContainText("Checked in ✓ WOD");
      await expect(page.getByTestId("desk-result")).toContainText("Wallet card");
      expect(calls.scans).toEqual([{ code: "W1walletcode", auto: true }]);
      expect(calls.checkIns).toEqual([]);
    });
  });

  test("Settings › Check-in asks before going back to rotating codes", async ({ page }) => {
    await common(page, "admin");
    const saved: Array<Record<string, unknown>> = [];
    let rules: Record<string, unknown> = {
      window_before_minutes: 30,
      window_after_minutes: 15,
      open_gym_requires_package: true,
      visitor_trial_offer: true,
      desk_override: false,
      door_rotation_seconds: 30,
      member_code_mode: "static",
    };
    await page.route("**/api/org/*/admin/check-in/settings", (route) => {
      if (route.request().method() === "PUT") {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        saved.push(body);
        rules = { ...rules, ...body };
      }
      return route.fulfill(json({ settings: rules }));
    });

    await page.goto("/admin/check-in/settings");
    await page.getByRole("radio", { name: /Changes/ }).check();
    await page.getByRole("button", { name: "Save" }).click();
    const confirm = page.getByTestId("mode-confirm");
    await expect(confirm).toContainText("revokes every fixed code", { ignoreCase: true });
    expect(saved).toEqual([]);

    await confirm.getByRole("button", { name: "No, leave it" }).click();
    await expect(confirm).toBeHidden();
    await page.getByRole("button", { name: "Save" }).click();
    await page.getByRole("button", { name: "Yes, revoke codes and cards" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Saved." })).toBeVisible();
    expect(saved).toEqual([expect.objectContaining({ member_code_mode: "rotating" })]);

    // Saved as rotating: a later save doesn't ask again.
    await page.getByRole("radiogroup", { name: "The door code changes every" }).getByText("15 seconds").click();
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.getByTestId("mode-confirm")).toBeHidden();
    await expect.poll(() => saved.length).toBe(2);
  });

  test("Me › Connected devices revokes a Wallet card", async ({ page }) => {
    await common(page, "member");
    const pass = { id: "pass-1", active: true, platform: "apple", added_at: "2026-10-01T10:00:00Z", box: { name: "Box Kypseli", slug: "kypseli", organization_id: "org-1" } };
    const deletes: string[] = [];
    await page.route("**/api/me/devices", (route) =>
      route.fulfill(
        json({
          wallet: { passes: [pass], platforms: { apple: true, google: false } },
          calendar: { https_url: "https://example.com/cal.ics", webcal_url: "webcal://example.com/cal.ics", download_url: "https://example.com/cal.ics?download=1" },
          integrations: [
            { provider: "garmin", status: "unavailable" },
            { provider: "apple_health", status: "native_only" },
          ],
        }),
      ),
    );
    await page.route("**/api/me/wallet-passes/pass-1", (route) => {
      deletes.push(route.request().method());
      return route.fulfill(json({ pass: { ...pass, active: false, revoked_at: new Date().toISOString() } }));
    });

    await page.goto("/me/devices");
    const wallet = page.getByTestId("devices-wallet");
    await expect(wallet).toContainText("Box Kypseli");
    await expect(page.getByTestId("devices-calendar").getByRole("link", { name: "Subscribe" })).toHaveAttribute("href", "webcal://example.com/cal.ics");
    await expect(page.getByTestId("garmin-row")).toContainText("Coming soon");
    await expect(page.getByTestId("devices-integrations")).toContainText("With the app");

    await page.getByTestId("revoke-pass-1").click();
    await wallet.getByRole("button", { name: "Yes, revoke" }).click();
    await expect(wallet.getByRole("status")).toHaveText("The card was revoked and your code at Box Kypseli changed.");
    await expect(wallet).toContainText("You don't have a card in a Wallet.");
    expect(deletes).toEqual(["DELETE"]);
  });
});
