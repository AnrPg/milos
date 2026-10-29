import { expect, test, type Page, type Route } from "./support/test";

// Χρήστες › Εισαγωγή (ADR-254, mockup s9 option B): drop the export, the
// source is recognised and the dry run shows at once; only the decisions
// that need a person are asked, «Εισαγωγή» runs in the background, then the
// report offers invitations and undo. The API is stubbed.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

function tokenFor(id: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

const membership = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, manage_users: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const header = ["First Name", "Last Name", "Email", "Membership", "Coach Notes"];
const baseMapping = [
  { column: 0, field: "first_name" },
  { column: 1, field: "last_name" },
  { column: 2, field: "email" },
  { column: 3, field: "package_name" },
];
const rows = [
  { id: "r2", row_number: 2, cells: ["Maria", "K", "maria@example.com", "Gold 2024", "Shoulder"], status: "pending", outcome: "create_person", warnings: [{ code: "package_created", field: "package_name" }], errors: [], result: {} },
  { id: "r3", row_number: 3, cells: ["Nikos", "A", "nikos@", "Gold 2024", ""], status: "pending", outcome: "create_person", warnings: [{ code: "invalid_email", field: "email" }], errors: [], result: {} },
  { id: "r4", row_number: 4, cells: ["", "", "", "", ""], status: "pending", outcome: "invalid", warnings: [], errors: [{ code: "missing_person", field: null }], result: {} },
];

type Write = { path: string; body: unknown };

async function stub(page: Page, writes: Write[]) {
  let current: Record<string, unknown> | null = null;
  let polls = 0;
  const preview = (mapping: unknown) => ({
    rows: 3,
    outcomes: { create_person: 2, invalid: 1 },
    actions: (mapping as Array<{ field: string }>).some((m) => m.field === "package_name")
      ? { create_person: 2, assign_package: 2, create_package: 1 }
      : { create_person: 2 },
    warnings: { invalid_email: 1 },
  });

  await page.route("**/api/**", async (route) => {
    const request = route.request();
    const path = tenantless(new URL(request.url()).pathname);
    const method = request.method();
    let body: unknown = null;
    if (method !== "GET") {
      try {
        body = request.postDataJSON();
      } catch {
        body = "multipart";
      }
      writes.push({ path, body });
    }
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner.id), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [membership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/imports/catalog") {
      return json(route, { presets: [{ key: "wodify", name: "Wodify", date_order: "mdy" }, { key: "excel", name: "Excel", date_order: "dmy" }], fields: [], date_orders: ["dmy", "mdy", "ymd"], roles: [], limits: {}, statuses: [], row_statuses: [], outcomes: [], warnings: [], errors: [], encodings: [] });
    }
    if (path === "/api/admin/imports" && method === "GET") return json(route, { imports: current ? [current] : [] });
    if (path === "/api/admin/imports" && method === "POST") {
      current = { id: "imp-1", status: "draft", source: "wodify", filename: "wodify-members.csv", byte_size: 512, encoding: "utf-8", delimiter: ",", header, row_count: 3, mapping: baseMapping, date_order: "mdy", default_role: "member", file_warnings: [], preview: null, counts: { statuses: { pending: 3 }, outcomes: {} }, inserted_at: "2026-10-29T10:00:00Z" };
      return json(route, { import: current }, 201);
    }
    if (path === "/api/admin/imports/imp-1/preview") {
      const mapping = (body as { mapping?: unknown })?.mapping ?? (current!.mapping as unknown);
      current = { ...current!, mapping, preview: preview(mapping), previewed_at: new Date().toISOString(), counts: { statuses: { pending: 3 }, outcomes: { create_person: 2, invalid: 1 } } };
      return json(route, { import: current });
    }
    if (path === "/api/admin/imports/imp-1/rows") return json(route, { rows, next_after_row: null });
    if (path === "/api/admin/imports/imp-1/apply") {
      current = { ...current!, status: "applying", counts: { statuses: { applied: 1, pending: 2 }, outcomes: {} } };
      return json(route, { import: current }, 202);
    }
    if (path === "/api/admin/imports/imp-1" && method === "GET") {
      if (current?.status === "applying" && ++polls >= 2) {
        current = {
          ...current,
          status: "applied",
          finished_at: "2026-10-29T10:05:00Z",
          undo_until: "2999-11-05T10:05:00Z",
          summary: { people_created: 2, people_matched: 0, subscriptions: 0 },
          counts: { statuses: { applied: 2, skipped: 1 }, outcomes: { create_person: 2, invalid: 1 } },
        };
      }
      return json(route, { import: current });
    }
    if (path === "/api/admin/imports/imp-1/invitations") return json(route, { sent: 1, failed: 0, remaining: 0, results: [] });
    if (path === "/api/admin/imports/imp-1/undo") {
      current = { ...current!, status: "undone", undone_at: "2026-10-29T11:00:00Z" };
      return json(route, { import: current });
    }
    if (path === "/api/admin/users") return json(route, { users: [] });
    return json(route, {});
  });
}

test("drop the export, answer the decisions, import, invite and undo", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/users/import");

  await expect(page.getByRole("heading", { name: "Import from other software" })).toBeVisible();
  await expect(page.getByText("Nothing changes until you press «Import».")).toBeVisible();

  await page.getByLabel("Choose a CSV file").setInputFiles({
    name: "wodify-members.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(`${header.join(",")}\nMaria,K,maria@example.com,Gold 2024,Shoulder\n`),
  });

  await expect(page).toHaveURL(/\/admin\/users\/import\?import=imp-1/);
  await expect(page.getByTestId("import-recognized")).toContainText("Recognised: an export from Wodify · 3 rows");
  await expect(page.getByTestId("import-kpis")).toContainText("new box members");
  await expect(page.getByTestId("import-decisions-title")).toHaveText("Need your decision · 3");

  const apply = page.getByTestId("import-apply");
  await expect(apply).toHaveText("Import 2 box members");
  await expect(apply).toBeDisabled();

  await page.getByTestId("import-decision-packages").getByRole("button", { name: "New package «Gold 2024»" }).click();
  await page.getByRole("button", { name: "Fine, I will fix them later" }).click();
  await page.getByTestId("import-decision-column").getByRole("button", { name: "Notes (staff only)" }).click();
  await expect(page.getByTestId("import-decisions-title")).toHaveText("All set");
  await expect.poll(() => (writes.filter((w) => w.path.endsWith("/preview")).at(-1)?.body as { mapping?: unknown })?.mapping).toEqual([
    ...baseMapping,
    { column: 4, field: "notes" },
  ]);

  // The rows with their filters.
  await page.getByRole("button", { name: "See the rows" }).first().click();
  const dialog = page.getByTestId("import-rows");
  await expect(dialog.getByText("Maria K · maria@example.com")).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Skipped · 1" })).toBeVisible();
  await dialog.getByRole("button", { name: "Close" }).click();

  await expect(apply).toBeEnabled();
  await apply.click();
  await expect(page.getByTestId("import-applying").or(page.getByTestId("import-report"))).toBeVisible();
  await expect(page.getByTestId("import-report")).toContainText("2 box members imported", { timeout: 15_000 });
  await expect(page.getByTestId("import-report")).toContainText("1 row was skipped");

  await page.getByRole("button", { name: "Send invitations now" }).click();
  await expect(page.getByText("1 invitation sent")).toBeVisible();

  await page.getByRole("button", { name: "Undo import" }).click();
  await page.getByTestId("import-undo-confirm").click();
  await expect(page.getByTestId("import-undone")).toContainText("The import was undone");
  expect(writes.map((w) => w.path)).toEqual(
    expect.arrayContaining(["/api/admin/imports", "/api/admin/imports/imp-1/apply", "/api/admin/imports/imp-1/invitations", "/api/admin/imports/imp-1/undo"]),
  );
});
