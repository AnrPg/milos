import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { AtlasScreen } from "./AtlasScreen";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/anatomy/renderer/figure-controller", () => ({ createFigure: () => new Promise(() => undefined) }));
vi.mock("@/lib/anatomy/renderer/thumbs", () => ({ renderThumb: () => new Promise(() => undefined) }));

const replace = vi.fn();
let search = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace, push: vi.fn() }),
  useSearchParams: () => search,
}));

const atlas = {
  range: "4w",
  weeks: 4,
  from: "2026-09-24",
  to: "2026-10-21",
  taxonomy_version: 1,
  thresholds: { medium: 3, high: 8 },
  sessions: 3,
  felt_entries: 1,
  exercises: { recognized: 3, unrecognized: 1 },
  nodes: [
    { id: "thighs", kind: "region", sets: 14, per_week: 3.5, level: "medium", felt: 1, top_exercises: [] },
    {
      id: "quadriceps",
      kind: "group",
      sets: 12.5,
      per_week: 3.1,
      level: "medium",
      felt: 1,
      top_exercises: [
        { exercise_ref: "back-squat", label: "Back Squat", sets: 8 },
        { exercise_ref: "deadlift", label: "Deadlift", sets: 2.5 },
      ],
    },
  ],
};

const exercises = {
  node_id: "quadriceps",
  videos_included: true,
  exercises: [
    {
      exercise_ref: "back-squat",
      label: "Back Squat",
      role: "primary",
      videos: [{ id: "v1", title: "Squat basics", video_url: "https://videos.example/squat", duration_minutes: 5 }],
    },
    ...["front-squat", "air-squat", "goblet-squat", "box-squat", "split-squat"].map((ref) => ({
      exercise_ref: ref,
      label: ref,
      role: "primary",
      videos: [],
    })),
  ],
};

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        <AtlasScreen />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  apiRequest.mockReset();
  replace.mockReset();
  search = new URLSearchParams();
  apiRequest.mockImplementation(async (path: string) => {
    if (path.startsWith("/me/atlas")) return atlas;
    if (path.startsWith("/anatomy/nodes/")) return exercises;
    return {};
  });
});

describe("AtlasScreen", () => {
  it("starts on the whole body and drills region › group with the breadcrumb", async () => {
    wrap();
    const panel = await screen.findByTestId("atlas-panel");
    expect(apiRequest).toHaveBeenCalledWith("/me/atlas?range=4w", { token: "token", scope: "account" });
    await within(panel).findByRole("heading", { name: "Whole body" });
    expect(panel).toHaveTextContent("1 exercise was not recognised and does not count.");

    fireEvent.click(within(panel).getByRole("button", { name: /Thighs/ }));
    expect(replace).toHaveBeenCalledWith("/journal/atlas?node=thighs", { scroll: false });
    await within(panel).findByRole("heading", { name: "Thighs" });

    fireEvent.click(within(panel).getByRole("button", { name: /Quadriceps/ }));
    await within(panel).findByRole("heading", { name: "Quadriceps" });
    const crumbs = within(panel).getByRole("navigation", { name: "Level" });
    expect(crumbs).toHaveTextContent("Body›Thighs›Quadriceps");

    fireEvent.click(within(crumbs).getByRole("button", { name: "Body" }));
    await within(panel).findByRole("heading", { name: "Whole body" });
  });

  it("shows what a group does, the member's sets and the gym's exercises with videos", async () => {
    search = new URLSearchParams("node=quadriceps");
    wrap();
    const panel = await screen.findByTestId("atlas-panel");
    await within(panel).findByRole("heading", { name: "Quadriceps" });
    expect(panel).toHaveTextContent(en.Anatomy.about.quadriceps);

    const sets = await within(panel).findByTestId("atlas-your-sets");
    expect(sets).toHaveTextContent("Yours · 4 wks");
    expect(sets).toHaveTextContent("12.5 sets");
    expect(sets).toHaveTextContent("Medium coverage");
    expect(sets).toHaveTextContent("Mostly from: Back Squat and Deadlift");
    expect(sets).toHaveTextContent("You felt it in 1 workout");

    const list = await within(panel).findByTestId("atlas-exercises");
    const video = await within(list).findByRole("link", { name: "Video: Squat basics" });
    expect(video).toHaveAttribute("href", "https://videos.example/squat");
    expect(within(list).queryByText("split-squat")).not.toBeInTheDocument();
    fireEvent.click(within(list).getByRole("button", { name: "All (6)" }));
    expect(within(list).getByText("split-squat")).toBeInTheDocument();

    // Heads of the group, and the range changes the query.
    fireEvent.click(within(panel).getByRole("button", { name: /Rectus femoris/ }));
    await within(panel).findByRole("heading", { name: "Rectus femoris" });
    expect(within(panel).getByTestId("atlas-your-sets")).toHaveTextContent("No sets here in this period.");
    fireEvent.click(screen.getByRole("button", { name: "12 wks" }));
    await waitFor(() => expect(apiRequest).toHaveBeenCalledWith("/me/atlas?range=12w", { token: "token", scope: "account" }));
  });

  it("explains an empty period and an unreachable exercise list", async () => {
    apiRequest.mockImplementation(async (path: string) => {
      if (path.startsWith("/me/atlas")) return { ...atlas, sessions: 0, nodes: [], exercises: { recognized: 0, unrecognized: 0 } };
      throw new Error("no gym");
    });
    search = new URLSearchParams("node=glutes");
    wrap();
    const panel = await screen.findByTestId("atlas-panel");
    await within(panel).findByRole("heading", { name: "Glutes" });
    expect(within(panel).getByTestId("atlas-your-sets")).toHaveTextContent("No workouts in this period yet.");
    expect(await within(panel).findByText("Exercises show once a box is selected.")).toBeInTheDocument();
  });

  it("heat-map mode shows the legend with its caveat", async () => {
    wrap();
    fireEvent.click(await screen.findByRole("radio", { name: "My coverage" }));
    expect(screen.getByText("An indication of your training volume, not a target.")).toBeInTheDocument();
    expect(screen.getByText("High")).toBeInTheDocument();
  });
});
