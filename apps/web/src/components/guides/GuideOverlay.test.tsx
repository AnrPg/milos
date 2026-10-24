import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { guideById } from "@/lib/guides/registry";
import { visibleSteps } from "@/lib/guides/engine";

import { GuideOverlay } from "./GuideOverlay";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, string>) => (values?.label ? `${key}[${values.label}]` : key),
}));
const push = vi.fn();
let pathname = "/org/box-a/admin/shop";
vi.mock("next/navigation", () => ({
  usePathname: () => pathname,
  useRouter: () => ({ push }),
  useSearchParams: () => new URLSearchParams(""),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "t" } }) }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "box-a" }));

const goTo = vi.fn();
const finish = vi.fn();
const dismiss = vi.fn();
let index = 0;
vi.mock("./GuideProvider", () => ({
  useOptionalGuides: () => {
    const guide = guideById("shop_staff");
    const abilities = { staff: true, manager: true, demo: false, hosts: false, inGymClub: false };
    return { active: { guide, steps: visibleSteps(guide, abilities), index }, abilities, routeParams: {}, goTo, finish, dismiss };
  },
}));

function wrap(children: ReactNode) {
  return <QueryClientProvider client={new QueryClient()}>{children}</QueryClientProvider>;
}

/** jsdom lays nothing out: give every element a box so anchors count as on screen. */
function layOut() {
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue({
    left: 100, top: 100, right: 300, bottom: 140, width: 200, height: 40, x: 100, y: 100, toJSON: () => ({}),
  } as DOMRect);
}

describe("GuideOverlay (ADR-193)", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["setInterval", "clearInterval", "setTimeout", "clearTimeout", "requestAnimationFrame", "cancelAnimationFrame", "performance"] });
    goTo.mockReset();
    finish.mockReset();
    dismiss.mockReset();
    push.mockReset();
    pathname = "/org/box-a/admin/shop";
    layOut();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    document.querySelectorAll("[data-test-anchor]").forEach((node) => node.remove());
  });

  it("explains the first step and moves on with Next", () => {
    index = 0;
    render(wrap(<GuideOverlay />));
    expect(screen.getByText("shop_staff.welcome.title")).toBeTruthy();
    fireEvent.click(screen.getByTestId("guide-next"));
    expect(goTo).toHaveBeenCalledWith(1);
  });

  it("waits for the person's tap, then for the screen it opens", () => {
    index = 1;
    const button = document.createElement("a");
    button.setAttribute("data-guide", "shop.newProduct");
    button.setAttribute("data-test-anchor", "");
    document.body.appendChild(button);
    render(wrap(<GuideOverlay />));
    act(() => void vi.advanceTimersByTime(300));
    // The label is the real button's, quoted in the copy.
    expect(screen.getByText("shop_staff.newProduct.body[ShopConsole.newProduct]")).toBeTruthy();
    expect(screen.getByText("ui.tapHint")).toBeTruthy();

    fireEvent.click(button);
    act(() => void vi.advanceTimersByTime(500));
    expect(goTo).not.toHaveBeenCalled();

    const editor = document.createElement("section");
    editor.setAttribute("data-guide", "shop.editor.photos");
    editor.setAttribute("data-test-anchor", "");
    document.body.appendChild(editor);
    act(() => void vi.advanceTimersByTime(300));
    expect(goTo).toHaveBeenCalledWith(2);
  });

  it("explains a step in the middle when its spot is not on screen", () => {
    index = 2;
    render(wrap(<GuideOverlay />));
    act(() => void vi.advanceTimersByTime(3000));
    expect(screen.getByText("ui.notHere")).toBeTruthy();
  });

  it("opens the step's page when it is elsewhere", () => {
    index = visibleSteps(guideById("shop_staff"), { staff: true, manager: true, demo: false, hosts: false, inGymClub: false }).findIndex((step) => step.id === "stock");
    render(wrap(<GuideOverlay />));
    expect(push).toHaveBeenCalledWith("/org/box-a/admin/shop?tab=stock");
  });

  it("Escape ends the guide before a dialog under it sees the key", () => {
    index = 3;
    const dialogKey = vi.fn();
    document.addEventListener("keydown", dialogKey);
    render(wrap(<GuideOverlay />));
    fireEvent.keyDown(window, { key: "Escape" });
    expect(dismiss).toHaveBeenCalled();
    expect(dialogKey).not.toHaveBeenCalled();
    document.removeEventListener("keydown", dialogKey);
  });
});
