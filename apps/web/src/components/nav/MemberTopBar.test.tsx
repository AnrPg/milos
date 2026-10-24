import { act, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { MemberTopBar } from "@/components/nav/MemberTopBar";
import { TopBarActions } from "@/components/nav/top-bar-slot";

let pathname = "/";
let unread = 0;
let memberships: unknown[] = [{ id: "m1" }];
let role = "member";
const openNotifications = vi.fn();

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
  useSession: () => ({ currentUser: { id: "u1", nickname: "Maria", role: "member" } }),
}));

vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ role, memberships, isLoading: false }),
}));

vi.mock("@/components/notifications/NotificationBell", () => ({
  openNotifications: () => openNotifications(),
  useUnreadNotifications: () => unread,
}));

vi.mock("@/components/chat/use-messages-unread", () => ({
  useMessagesUnread: () => 0,
}));

vi.mock("@/components/account/ProfileSwitcherMenu", () => ({
  ProfileSwitcherMenu: () => null,
}));

beforeEach(() => {
  pathname = "/";
  unread = 0;
  memberships = [{ id: "m1" }];
  role = "member";
  openNotifications.mockReset();
});

describe("MemberTopBar", () => {
  it("has the logo on the left and the bell, which opens notifications, on the right", () => {
    unread = 4;
    render(<MemberTopBar />);
    expect(screen.getByRole("link", { name: "brandName" })).toHaveAttribute("href", "/");
    const bell = screen.getByRole("button", { name: 'notificationsUnread:{"count":4}' });
    act(() => bell.click());
    expect(openNotifications).toHaveBeenCalledTimes(1);
    expect(screen.getByTestId("member-top-bar")).toHaveAttribute("data-state", "shown");
    expect(screen.getByTestId("member-top-bar").textContent ?? "").not.toMatch(/\p{Extended_Pictographic}/u);
  });

  it("puts a page's action next to the bell", () => {
    render(
      <>
        <MemberTopBar />
        <TopBarActions>
          <button type="button">compose</button>
        </TopBarActions>
      </>,
    );
    const bar = screen.getByTestId("member-top-bar");
    expect(bar).toContainElement(screen.getByRole("button", { name: "compose" }));
  });

  it("keeps the action in the page when there is no top bar", () => {
    render(
      <TopBarActions>
        <button type="button">compose</button>
      </TopBarActions>,
    );
    expect(screen.getByRole("button", { name: "compose" })).toBeInTheDocument();
  });

  it("is not there on the hidden routes or in the staff console, but keeps the tab strip", () => {
    pathname = "/workouts/w1/execute";
    const { unmount } = render(<MemberTopBar>tabs</MemberTopBar>);
    expect(screen.queryByTestId("member-top-bar")).toBeNull();
    expect(screen.getByText("tabs")).toBeInTheDocument();
    unmount();
    pathname = "/";
    role = "admin";
    render(<MemberTopBar />);
    expect(screen.queryByTestId("member-top-bar")).toBeNull();
  });
});
