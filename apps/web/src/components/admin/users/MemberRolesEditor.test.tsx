import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { updateMemberRoles } from "@/api/roles";
import { MemberRolesEditor } from "./MemberRolesEditor";

const state = vi.hoisted(() => ({ actorRoles: ["owner"] as string[] }));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({
    membership: {
      role: state.actorRoles[0],
      roles: state.actorRoles,
      capabilities: { grant_staff_roles: "all", set_head_coach: "all" },
      location_scope: null,
    },
  }),
}));
vi.mock("@/api/facility", () => ({ listAdminLocations: vi.fn().mockResolvedValue([]) }));
vi.mock("@/api/roles", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/roles")>()),
  updateMemberRoles: vi.fn().mockResolvedValue({}),
}));

function renderEditor(userId: string, roles: string[]) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <MemberRolesEditor token="access" userId={userId} membership={{ roles, coach_scope: "own", location_scope: null }} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("Roles in this box (ADR-219)", () => {
  it("on my own profile, keeps my top role locked and lets me add a lower one", async () => {
    state.actorRoles = ["owner"];
    renderEditor("me", ["owner"]);

    expect(screen.getByRole("button", { name: "Owner" })).toBeDisabled();
    expect(screen.getByText(en.Ui.myRolesHelp)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Coach" }));
    fireEvent.click(screen.getByRole("button", { name: "Save roles" }));

    await waitFor(() => expect(updateMemberRoles).toHaveBeenCalledWith("access", "me", ["owner", "coach"]));
  });

  it("shows nothing to edit on a fellow admin or an owner", () => {
    state.actorRoles = ["admin"];
    const { container, rerender } = renderEditor("other", ["admin"]);
    expect(container).toBeEmptyDOMElement();

    rerender(
      <QueryClientProvider client={new QueryClient()}>
        <NextIntlClientProvider locale="en" messages={en}>
          <MemberRolesEditor token="access" userId="owner" membership={{ roles: ["owner"], coach_scope: "own" }} />
        </NextIntlClientProvider>
      </QueryClientProvider>,
    );
    expect(container).toBeEmptyDOMElement();
  });

  it("lets an admin change staff below them but not grant admin", () => {
    state.actorRoles = ["admin"];
    renderEditor("other", ["coach"]);

    expect(screen.queryByRole("button", { name: "Admin" })).toBeNull();
    expect(screen.getByRole("button", { name: "Front desk" })).toBeEnabled();
  });
});
