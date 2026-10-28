import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { ApiError } from "@/api/client";
import { updateMyRoles } from "@/api/roles";
import { MyRolesSection } from "./MyRolesSection";

const state = vi.hoisted(() => ({ membership: null as unknown as Record<string, unknown> | null }));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, status: "authenticated" }),
}));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membership: state.membership }) }));
vi.mock("@/api/roles", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/roles")>()),
  updateMyRoles: vi.fn(),
}));

function renderSection() {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <MyRolesSection />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

function membership(roles: string[]) {
  return { role: roles[0], roles, capabilities: {}, organization: { id: "org-1", slug: "box1", name: "Box One" } };
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("Settings › My roles (ADR-219)", () => {
  it("lets an owner add coach while owner stays locked", async () => {
    state.membership = membership(["owner"]);
    vi.mocked(updateMyRoles).mockResolvedValue({ user_id: "u", role: "owner", roles: ["owner", "coach"] });
    renderSection();

    fireEvent.click(screen.getByRole("button", { name: /My roles in this box/ }));
    const group = screen.getByRole("group", { name: "My roles in this box" });
    expect(within(group).getByRole("button", { name: "Owner" })).toBeDisabled();
    fireEvent.click(within(group).getByRole("button", { name: "Coach" }));
    fireEvent.click(screen.getByRole("button", { name: "Save roles" }));

    await waitFor(() => expect(updateMyRoles).toHaveBeenCalledWith("access", ["owner", "coach"]));
  });

  it("shows why the API refused", async () => {
    state.membership = membership(["coach"]);
    vi.mocked(updateMyRoles).mockRejectedValue(
      new ApiError(403, "locked", { code: "own_top_role_locked", error: "locked" }),
    );
    renderSection();

    fireEvent.click(screen.getByRole("button", { name: /My roles in this box/ }));
    const group = screen.getByRole("group", { name: "My roles in this box" });
    expect(within(group).queryByRole("button", { name: "Front desk" })).toBeNull();
    fireEvent.click(within(group).getByRole("button", { name: "Box member" }));
    fireEvent.click(screen.getByRole("button", { name: "Save roles" }));

    expect(await screen.findByText(en.Ui.apiErrorOwnTopRoleLocked)).toBeInTheDocument();
  });

  it("is hidden for members, who have nothing below them", () => {
    state.membership = membership(["member"]);
    const { container } = renderSection();
    expect(container).toBeEmptyDOMElement();
  });
});
