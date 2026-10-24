import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { BottomNav } from "@/components/nav/BottomNav";
import { useHideBottomNav } from "@/components/nav/bottom-nav-visibility";

let pathname = "/";
let unread = 0;
let memberships: unknown[] = [{ id: "m1" }];
let role = "member";
let currentUser: Record<string, unknown> | null = { id: "u1", nickname: "Maria", role: "member", avatar_url: null };

vi.mock("next/navigation", () => ({
  usePathname: () => pathname,
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock("next/link", () => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  default: ({ href, children, ...rest }: any) => (
    <a href={href} {...{ ...rest, prefetch: undefined }}>
      {children}
    </a>
  ),
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${JSON.stringify(values)}` : key),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ currentUser }),
}));

vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ role, memberships, isLoading: false }),
}));

vi.mock("@/components/chat/use-messages-unread", () => ({
  useMessagesUnread: () => unread,
}));

vi.mock("@/components/account/ProfileSwitcherMenu", () => ({
  ProfileSwitcherMenu: () => <div>switcher</div>,
}));

function HidingScreen() {
  useHideBottomNav();
  return null;
}

beforeEach(() => {
  pathname = "/";
  unread = 0;
  memberships = [{ id: "m1" }];
  role = "member";
  currentUser = { id: "u1", nickname: "Maria", role: "member", avatar_url: null };
});

describe("BottomNav", () => {
  it("shows Feed · Box · Journal · Μηνύματα · avatar and marks the current tab", () => {
    pathname = "/box/schedule";
    render(<BottomNav />);
    const nav = screen.getByRole("navigation", { name: "memberTabs" });
    expect(nav).toBeInTheDocument();
    const links = screen.getAllByRole("link");
    expect(links.map((link) => link.getAttribute("href"))).toEqual(["/", "/box", "/journal", "/messages", "/me"]);
    expect(screen.getByRole("link", { name: /box/ })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: /feed/ })).not.toHaveAttribute("aria-current");
    expect(screen.getByRole("link", { name: "me" })).toHaveAttribute("href", "/me");
    expect(screen.queryByRole("button", { name: "notifications" })).toBeNull();
    expect(document.documentElement.dataset.bottomNav).toBe("on");
  });

  it("puts the unread count on Μηνύματα and lights it in the inbox", () => {
    unread = 3;
    pathname = "/messages/c-1";
    render(<BottomNav />);
    const messages = screen.getByRole("link", { name: 'messagesUnread:{"count":3}' });
    expect(messages).toHaveAttribute("href", "/messages");
    expect(messages).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: /feed/ })).not.toHaveAttribute("aria-current");
    expect(screen.getByTestId("bottom-nav-badge")).toHaveTextContent("3");
  });

  it("caps the badge at 99+ and shows none at zero", () => {
    unread = 120;
    const { unmount } = render(<BottomNav />);
    expect(screen.getByTestId("bottom-nav-badge")).toHaveTextContent("99+");
    unmount();
    unread = 0;
    render(<BottomNav />);
    expect(screen.queryByTestId("bottom-nav-badge")).toBeNull();
  });

  it("is not there on the hidden routes, and gives the page no room there", () => {
    pathname = "/workouts/w1/execute";
    render(<BottomNav />);
    expect(screen.queryByRole("navigation")).toBeNull();
    expect(document.documentElement.dataset.bottomNav).toBeUndefined();
  });

  it("steps aside while a screen asks with useHideBottomNav()", () => {
    const { rerender } = render(
      <>
        <BottomNav />
        <HidingScreen />
      </>,
    );
    const nav = screen.getByTestId("bottom-nav");
    expect(nav).toHaveAttribute("data-state", "hidden");
    expect(nav).toHaveAttribute("aria-hidden", "true");
    rerender(<BottomNav />);
    expect(screen.getByTestId("bottom-nav")).toHaveAttribute("data-state", "shown");
  });

  it("shows for a signed-in person without any membership", () => {
    memberships = [];
    render(<BottomNav />);
    expect(screen.getByRole("navigation", { name: "memberTabs" })).toBeInTheDocument();
  });

  it("stays away in the staff console and when signed out", () => {
    role = "admin";
    const { unmount } = render(<BottomNav />);
    expect(screen.queryByRole("navigation")).toBeNull();
    unmount();
    role = "member";
    currentUser = null;
    render(<BottomNav />);
    expect(screen.queryByRole("navigation")).toBeNull();
  });

  it("uses outline icons, never emoji", () => {
    render(<BottomNav />);
    const text = screen.getByTestId("bottom-nav").textContent ?? "";
    expect(text).not.toMatch(/\p{Extended_Pictographic}/u);
    expect(screen.getByTestId("bottom-nav").querySelectorAll("svg[stroke='currentColor']").length).toBe(4);
  });
});
