import { render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { ClassRoomDialog } from "./ClassRoomDialog";

const fetchClassRoom = vi.fn();

vi.mock("@/api/schedule", () => ({ fetchClassRoom: (...args: unknown[]) => fetchClassRoom(...args) }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

const room = {
  space: { id: "s1", name: "Studio", description: null, directions: "First floor, left" },
  floor_plan: { id: "f1", name: "First floor", image_url: "https://img/plan.jpg" },
  area: { points: [[0.1, 0.1], [0.5, 0.1], [0.5, 0.4], [0.1, 0.4]] },
  photos: [{ id: "ph1", url: "https://img/room.jpg", caption: "Mirrors" }],
};

function renderDialog() {
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        <ClassRoomDialog slotId="slot-1" spaceName="Studio" onClose={() => {}} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("ClassRoomDialog", () => {
  beforeEach(() => fetchClassRoom.mockReset());

  it("shows the room coloured on its floor plan, the way there and its photos", async () => {
    fetchClassRoom.mockResolvedValue(room);
    renderDialog();

    expect(await screen.findByTestId("class-room-plan")).toBeInTheDocument();
    expect(fetchClassRoom).toHaveBeenCalledWith("token", "slot-1");
    expect(screen.getByTestId("plan-area-s1")).toHaveTextContent("Studio");
    expect(screen.getByTestId("class-room-directions")).toHaveTextContent("First floor, left");
    expect(screen.getByTestId("class-room-photos")).toBeInTheDocument();
  });

  it("a hidden floor shows the room without its plan", async () => {
    fetchClassRoom.mockResolvedValue({ ...room, floor_plan: null, area: null });
    renderDialog();

    await waitFor(() => expect(screen.getByTestId("class-room-directions")).toBeInTheDocument());
    expect(screen.queryByTestId("class-room-plan")).not.toBeInTheDocument();
  });
});
