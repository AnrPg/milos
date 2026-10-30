import { expect, test, type Page } from "./support/test";

// ADR-280: the Palee team's console for Partners. «Training partner
// verifications»: compare the selfie and its code with the avatar, approve,
// or reject with a required reason. «Training partner reports»: open reports
// per person, suspend (confirmed in the page) or dismiss, and the «Suggestion
// quality» counters. The API is stubbed; every route not listed answers an
// empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });

async function signedInVendor(page: Page) {
  const user = {
    id: "vendor-1",
    nickname: "Palee",
    role: "admin",
    email: "vendor-1@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: true,
    memberships: [],
  };
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: "admin", memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString(
    "base64url",
  );
  const token = `stub.${payload}.signature`;
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh", user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

const queueItem = (id: string, nickname: string) => ({
  id,
  status: "in_review",
  overdue: false,
  person: person(`person-${id}`, nickname),
  submitted_at: "2026-10-30T09:00:00Z",
  selfie_expires_at: "2026-11-06T09:00:00Z",
});

const detail = (id: string, nickname: string) => ({
  id,
  status: "in_review",
  person: person(`person-${id}`, nickname),
  consent_at: "2026-10-29T09:00:00Z",
  submitted_at: "2026-10-30T09:00:00Z",
  decided_at: null,
  decision_reason: null,
  phone: "+30 69•• •••• 78",
  phone_verified: true,
  selfie_code: "4827",
  selfie_url: "/__selfie/req.png",
  selfie_url_expires_in: 300,
  selfie_uploaded_at: "2026-10-30T09:00:00Z",
  selfie_expires_at: "2026-11-06T09:00:00Z",
  sponsors: [
    { person: person("dimitra", "Dimitra"), channel: "buddy", vouched_at: "2026-10-29T12:00:00Z" },
    { person: person("nikos", "Nikos"), channel: "link", vouched_at: "2026-10-29T13:00:00Z" },
  ],
});

async function verificationQueue(page: Page) {
  let queue = [queueItem("req-1", "Giorgos"), queueItem("req-2", "Eleni")];
  await page.route("**/api/platform/partner-verifications?**", (route) => route.fulfill(json({ requests: queue })));
  await page.route("**/api/platform/partner-verifications/req-1", (route) => route.fulfill(json(detail("req-1", "Giorgos"))));
  await page.route("**/api/platform/partner-verifications/req-2", (route) => route.fulfill(json(detail("req-2", "Eleni"))));
  await page.route("**/__selfie/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: Buffer.alloc(0) }));
  const decisions: { id: string; body: unknown }[] = [];
  await page.route("**/api/platform/partner-verifications/*/decision", (route) => {
    const id = route.request().url().split("/").at(-2) ?? "";
    decisions.push({ id, body: route.request().postDataJSON() });
    queue = queue.filter((item) => item.id !== id);
    return route.fulfill(json({ id, status: "approved", decided_at: "2026-10-30T10:00:00Z" }));
  });
  return decisions;
}

test.describe("platform partners", () => {
  test("the Palee team compares the selfie and its code with the avatar and approves", async ({ page }) => {
    await signedInVendor(page);
    const decisions = await verificationQueue(page);
    await page.goto("/platform/partner-verifications");

    await expect(page.getByRole("heading", { name: "Training partner verifications" })).toBeVisible();
    await page.getByTestId("verification-row-req-1").click();

    const panel = page.getByTestId("verification-detail");
    await expect(panel.getByTestId("verification-code")).toHaveText("4827");
    await expect(panel.getByText("Avatar", { exact: true })).toBeVisible();
    await expect(panel.getByText("Dimitra")).toBeVisible();
    await expect(panel.getByText("+30 69•• •••• 78")).toBeVisible();
    await expect(panel.getByText("The photo is deleted as soon as you decide.", { exact: false })).toBeVisible();
    await panel.getByRole("button", { name: "Approve" }).click();

    await expect(page.getByText("Giorgos is verified.")).toBeVisible();
    expect(decisions).toEqual([{ id: "req-1", body: { decision: "approve" } }]);
    await expect(page.getByTestId("verification-row-req-1")).toHaveCount(0);
  });

  test("rejecting needs a reason, written under the field", async ({ page }) => {
    await signedInVendor(page);
    const decisions = await verificationQueue(page);
    await page.goto("/platform/partner-verifications");
    await page.getByTestId("verification-row-req-2").click();

    const panel = page.getByTestId("verification-detail");
    await panel.getByRole("button", { name: "Reject…" }).click();
    await panel.getByRole("button", { name: "Reject", exact: true }).click();
    await expect(panel.getByText("Write a reason to reject.")).toBeVisible();
    expect(decisions).toEqual([]);

    await panel.getByLabel("Reason (the person sees it)").fill("The code is not readable. Take a new selfie in daylight.");
    await panel.getByRole("button", { name: "Reject", exact: true }).click();
    await expect(page.getByText("Eleni was rejected.")).toBeVisible();
    expect(decisions).toEqual([
      { id: "req-2", body: { decision: "reject", reason: "The code is not readable. Take a new selfie in daylight." } },
    ]);
  });

  test("the Palee team suspends a reported person after confirming, and sees the suggestion quality", async ({ page }) => {
    await signedInVendor(page);
    const report = (id: string, reason: string, reporter: string) => ({
      id,
      reason,
      note: reason === "minor" ? "Says they are 16" : null,
      status: "open",
      created_at: "2026-10-29T10:00:00Z",
      decided_at: null,
      decision_note: null,
      reports_on_target: 2,
      reporter: person(`reporter-${id}`, reporter),
      target: person("kostas", "Kostas"),
    });
    let reports = [report("rep-1", "minor", "Maria"), report("rep-2", "fake", "Nikos")];
    await page.route("**/api/platform/partner-reports?**", (route) => route.fulfill(json({ reports })));
    const decisions: { url: string; body: unknown }[] = [];
    await page.route("**/api/platform/partner-reports/*/decision", (route) => {
      decisions.push({ url: route.request().url(), body: route.request().postDataJSON() });
      reports = [];
      return route.fulfill(json({ id: "rep-1", decision: "suspend", target_id: "kostas", resolved: 2, penalized_sponsors: 1 }));
    });
    await page.route("**/api/platform/partner-suggestion-stats", (route) =>
      route.fulfill(
        json({
          since: "2026-10-01",
          days: [
            { day: "2026-10-29", shown: 30, proposed: 6, booked_together: 0, feedback: 2 },
            { day: "2026-10-30", shown: 10, proposed: 4, booked_together: 0, feedback: 1 },
          ],
          feedback_reasons: { not_near: 1, bad_time: 2, wrong_level: 0, other: 0 },
        }),
      ),
    );
    await page.goto("/platform/partner-reports");

    await expect(page.getByRole("heading", { name: "Training partner reports" })).toBeVisible();
    const group = page.getByTestId("report-group-kostas");
    await expect(group.getByText("2 open reports")).toBeVisible();
    await expect(group.getByText("Minor").first()).toBeVisible();
    await expect(group.getByText("Says they are 16")).toBeVisible();

    await group.getByLabel("Note (internal, optional)").fill("Minor, confirmed by two reports");
    await group.getByRole("button", { name: "Suspend" }).click();
    await expect(group.getByText("Suspend Kostas?", { exact: false })).toBeVisible();
    await group.getByRole("button", { name: "Yes, suspend" }).click();

    await expect(page.getByText("Kostas was suspended. 1 sponsor was paused.")).toBeVisible();
    expect(decisions).toHaveLength(1);
    expect(decisions[0].url).toContain("/api/platform/partner-reports/rep-1/decision");
    expect(decisions[0].body).toEqual({ decision: "suspend", note: "Minor, confirmed by two reports" });
    await expect(page.getByText("No open reports.")).toBeVisible();

    const stats = page.getByTestId("suggestion-stats");
    await expect(stats.getByRole("heading", { name: "Suggestion quality" })).toBeVisible();
    await expect(stats.getByText("40", { exact: true })).toBeVisible();
    await expect(stats.getByText("25%")).toBeVisible();
  });
});
