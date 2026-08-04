import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { OrganizationSelector } from "@/components/organization-selector";

const push = vi.fn();
let membershipData: unknown[] = [];

vi.mock("next/navigation", () => ({
  usePathname: () => "/org/milos",
  useRouter: () => ({ push }),
}));

vi.mock("@tanstack/react-query", () => ({
  useQuery: () => ({ data: membershipData }),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" } }),
}));

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

describe("OrganizationSelector", () => {
  it("does not render when the user only belongs to one organization", () => {
    membershipData = [
      {
        id: "membership-1",
        role: "member",
        organization: { slug: "milos", name: "Milos Training" },
        settings: null,
      },
    ];

    render(<OrganizationSelector variant="menu" />);

    expect(screen.queryByRole("combobox", { name: "organization" })).not.toBeInTheDocument();
  });

  it("renders a menu switcher for multi-organization users and routes to the selected organization", () => {
    membershipData = [
      {
        id: "membership-1",
        role: "member",
        organization: { slug: "milos", name: "Milos Training" },
        settings: null,
      },
      {
        id: "membership-2",
        role: "coach",
        organization: { slug: "atlas", name: "Atlas Gym" },
        settings: { brand_name: "Atlas Performance" },
      },
    ];
    const onSelect = vi.fn();

    render(<OrganizationSelector variant="menu" onSelect={onSelect} />);

    fireEvent.change(screen.getByRole("combobox", { name: "organization" }), {
      target: { value: "atlas" },
    });

    expect(push).toHaveBeenCalledWith("/admin");
    expect(onSelect).toHaveBeenCalledOnce();
  });
});
