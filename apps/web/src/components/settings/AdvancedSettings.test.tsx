import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { CatalogSetting } from "@/api/setup";

import { AdvancedDisclosure, settingLevels } from "./AdvancedSettings";
import { AdvancedSettingsCard, matchingGroups } from "./AdvancedSettingsCard";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: null }) }));

const setting = (key: string, verdict: CatalogSetting["verdict"]) => ({ key, verdict }) as CatalogSetting;
const catalog = [
  setting("scheduling.default_capacity", "basic"),
  setting("scheduling.default_booking_window_days", "advanced"),
  setting("gamification.streak_shields", "advanced"),
  setting("provider.kind", "derive"),
  setting("ai.model", "remove"),
];

function renderWith(node: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {node}
    </NextIntlClientProvider>,
  );
}

describe("settingLevels (ADR-255)", () => {
  it("shows basic settings, keeps advanced ones under «Advanced» and hides derived and removed ones", () => {
    const levels = settingLevels(catalog, ["scheduling.default_booking_window_days", "gamification.streak_shields"]);
    expect(levels.basic("scheduling.default_capacity")).toBe(true);
    expect(levels.advanced("scheduling.default_capacity")).toBe(false);
    expect(levels.advanced("gamification.streak_shields")).toBe(true);
    expect(levels.basic("gamification.streak_shields")).toBe(false);
    for (const key of ["provider.kind", "ai.model"]) {
      expect(levels.hidden(key)).toBe(true);
      expect(levels.basic(key)).toBe(false);
      expect(levels.advanced(key)).toBe(false);
    }
    expect(levels.advancedCount).toBe(2);
    expect(levels.ready).toBe(true);
  });

  it("before the catalog arrives, the settings' own list decides and nothing is basic without it", () => {
    const fromList = settingLevels(undefined, ["gamification.streak_shields"]);
    expect(fromList.basic("scheduling.default_capacity")).toBe(true);
    expect(fromList.advanced("gamification.streak_shields")).toBe(true);
    expect(fromList.ready).toBe(false);

    const nothing = settingLevels(undefined, undefined);
    expect(nothing.basic("scheduling.default_capacity")).toBe(false);
  });
});

describe("«Advanced»", () => {
  it("matches groups by title or keyword, without accents or case", () => {
    const groups = [
      { title: "Κρατήσεις", keywords: ["αναμονή"] },
      { title: "Κίνητρα", keywords: ["ασπίδα ασπίδες σερί"] },
    ];
    expect(matchingGroups(groups, "")).toHaveLength(2);
    expect(matchingGroups(groups, "ΑΣΠΙΔ").map((group) => group.title)).toEqual(["Κίνητρα"]);
    expect(matchingGroups(groups, "κρατησ").map((group) => group.title)).toEqual(["Κρατήσεις"]);
    expect(matchingGroups(groups, "zzz")).toEqual([]);
  });

  it("the card is closed by default, says how many settings it holds and narrows them by search", () => {
    renderWith(
      <AdvancedSettingsCard
        count={12}
        groups={[
          { id: "bookings", title: "Bookings", keywords: ["waitlist"], content: <p>Booking window</p> },
          { id: "motivation", title: "Motivation", keywords: ["shields"], content: <p>Streak shields</p> },
        ]}
      />,
    );
    const toggle = screen.getByRole("button", { name: /Advanced/ });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).toHaveTextContent("12 settings with a good default. People rarely change them.");
    expect(screen.queryByText("Streak shields")).not.toBeInTheDocument();

    fireEvent.click(toggle);
    expect(screen.getByText("Booking window")).toBeInTheDocument();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search settings" }), { target: { value: "shield" } });
    expect(screen.getByText("Streak shields")).toBeInTheDocument();
    expect(screen.queryByText("Booking window")).not.toBeInTheDocument();
    fireEvent.change(screen.getByRole("searchbox", { name: "Search settings" }), { target: { value: "nothing like it" } });
    expect(screen.getByText("No setting matches.")).toBeInTheDocument();
  });

  it("a disclosure inside one settings area opens on one tap", () => {
    renderWith(
      <AdvancedDisclosure count={2}>
        <p>Member groups</p>
      </AdvancedDisclosure>,
    );
    expect(screen.queryByText("Member groups")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Advanced/ }));
    expect(screen.getByText("Member groups")).toBeInTheDocument();
  });
});
