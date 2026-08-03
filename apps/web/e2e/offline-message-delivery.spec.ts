import { expect, test, type BrowserContext, type Route } from "@playwright/test";

const user = {
  id: "11111111-1111-4111-8111-111111111111",
  nickname: "Offline Sender",
  role: "member",
  avatar_url: null,
  preferred_locale: "en",
};
const recipient = {
  id: "22222222-2222-4222-8222-222222222222",
  nickname: "Training Partner",
  role: "member",
};
const thread = {
  id: "33333333-3333-4333-8333-333333333333",
  context_type: "direct",
  context_id: null,
  created_by_id: user.id,
  inserted_at: "2026-07-19T12:00:00Z",
  participants: [
    { id: "44444444-4444-4444-8444-444444444444", user_id: user.id, nickname: user.nickname, last_read_message_id: null },
    { id: "55555555-5555-4555-8555-555555555555", user_id: recipient.id, nickname: recipient.nickname, last_read_message_id: null },
  ],
};

test("an offline message survives page close and synchronizes exactly once", async ({
  context,
  page,
}) => {
  const deliveredMessages: Array<Record<string, unknown>> = [];
  await mockAuthenticatedApi(context, deliveredMessages);

  await page.goto("/about");
  await page.getByRole("button", { name: "Chat", exact: true }).click();
  await page.getByRole("button", { name: new RegExp(recipient.nickname, "i") }).click();

  await context.setOffline(true);
  await page.getByRole("textbox", { name: "Write a message" }).fill("Queued while offline");
  await page.getByRole("button", { name: "Send", exact: true }).click();

  await expect(page.getByText("Queued while offline")).toBeVisible();
  await expect(page.getByText(/Sending/)).toBeVisible();
  expect(deliveredMessages).toHaveLength(0);

  await page.close();
  await context.setOffline(false);

  const reopened = await context.newPage();
  await reopened.goto("/about");
  await expect.poll(() => deliveredMessages.length).toBe(1);

  await reopened.getByRole("button", { name: "Chat", exact: true }).click();
  await reopened.getByRole("button", { name: new RegExp(recipient.nickname, "i") }).click();
  await expect(reopened.getByText("Queued while offline")).toBeVisible();
  await expect(reopened.getByText(/Sending/)).toHaveCount(0);
});

async function mockAuthenticatedApi(
  context: BrowserContext,
  deliveredMessages: Array<Record<string, unknown>>,
) {
  await context.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const method = route.request().method();

    if (path === "/api/auth/refresh") return json(route, { access_token: "test-token" });
    if (path === "/api/auth/me") return json(route, user);
    if (path === "/api/threads/unread-count") return json(route, { unread_count: 0 });
    if (path === "/api/threads" && method === "GET") return json(route, { threads: [thread] });

    if (path === `/api/threads/${thread.id}/messages` && method === "POST") {
      const payload = route.request().postDataJSON() as Record<string, unknown>;
      const message = {
        id: "66666666-6666-4666-8666-666666666666",
        thread_id: thread.id,
        sender_id: user.id,
        body: payload.body,
        message_type: payload.message_type,
        client_operation_id: payload.client_operation_id,
        inserted_at: "2026-07-19T12:05:00Z",
      };
      deliveredMessages.push(message);
      return json(route, { message }, 201);
    }

    if (path === `/api/threads/${thread.id}/messages` && method === "GET") {
      return json(route, { messages: deliveredMessages });
    }

    if (path.startsWith("/api/notifications")) {
      return json(route, { notifications: [], unread_count: 0 });
    }
    if (path === "/api/my/finance") return json(route, {});
    if (path === "/api/theme") return json(route, {});

    return json(route, {});
  });
}

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
}
