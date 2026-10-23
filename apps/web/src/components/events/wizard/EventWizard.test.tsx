import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import { blankEventForm } from "../EventFormParts";
import type { EventForm } from "../events";
import { EventWizard } from "./EventWizard";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" }, status: "authenticated" }),
}));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationTimeZoneStatus: () => ({ zone: "Europe/Athens", confirmed: true }),
}));

const w = en.EventWizard;
const e = en.Events;
const LOCATIONS = [{ id: "loc-1", name: "Kypseli" }];

function wrap(ui: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const next = () => screen.getByRole("button", { name: w.next });

describe("EventWizard", () => {
  afterEach(() => {
    window.localStorage.clear();
  });

  it("walks a new event step by step, says why Next waits, and sends its co-hosts with it", async () => {
    const onSubmit = vi.fn().mockResolvedValue({ cohostFailures: [] });
    const onClose = vi.fn();
    wrap(
      <EventWizard
        title="New event"
        initial={blankEventForm(LOCATIONS)}
        locations={LOCATIONS}
        gymSlug="box"
        cohosts={{ ownSlug: "box" }}
        onSubmit={onSubmit}
        onClose={onClose}
      />,
    );

    const dialog = screen.getByRole("dialog", { name: "New event" });
    expect(within(dialog).getByRole("heading", { name: w.heading_basics })).toBeInTheDocument();
    expect(next()).toHaveAttribute("aria-disabled", "true");
    expect(next()).toHaveAccessibleDescription(e.problem_title);
    fireEvent.click(next());
    expect(screen.getByRole("alert")).toHaveTextContent(e.problem_title);
    expect(screen.getByRole("heading", { name: w.heading_basics })).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(e.fieldTitle), { target: { value: "Run up Lycabettus" } });
    expect(next()).not.toHaveAttribute("aria-disabled");
    fireEvent.click(next());
    expect(screen.getByRole("heading", { name: w.heading_when })).toHaveFocus();

    fireEvent.click(next());
    const place = screen.getByRole("radiogroup", { name: e.fieldPlace });
    expect(within(place).getByRole("radio", { name: "Kypseli" })).toHaveAttribute("aria-checked", "true");
    fireEvent.click(within(place).getByRole("radio", { name: e.placeElsewhere }));
    expect(next()).toHaveAccessibleDescription(e.problem_place);
    fireEvent.change(screen.getByLabelText(e.fieldPlaceName), { target: { value: "Lycabettus Hill" } });
    fireEvent.click(next());

    fireEvent.click(screen.getByRole("radio", { name: new RegExp(e.paid) }));
    expect(next()).toHaveAccessibleDescription(e.problem_price);
    fireEvent.change(screen.getByLabelText(e.fieldAmount), { target: { value: "15" } });
    fireEvent.click(next());

    expect(screen.getByRole("heading", { name: w.heading_capacityCohosts })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(e.fieldCapacity), { target: { value: "20" } });
    const slug = screen.getByLabelText(w.cohostSlug);
    fireEvent.change(slug, { target: { value: "box" } });
    fireEvent.click(screen.getByRole("button", { name: w.cohostAdd }));
    expect(screen.getByRole("alert")).toHaveTextContent(w.cohost_self);
    fireEvent.change(slug, { target: { value: "https://palee.app/b/box-kypseli" } });
    fireEvent.keyDown(slug, { key: "Enter" });
    expect(screen.getByRole("list", { name: w.cohostsTitle })).toHaveTextContent("box-kypseli");
    fireEvent.click(next());

    expect(screen.getByRole("heading", { name: w.heading_review })).toBeInTheDocument();
    expect(screen.getByText("Run up Lycabettus")).toBeInTheDocument();
    expect(screen.getByText("Lycabettus Hill")).toBeInTheDocument();
    expect(screen.getByText("20 places")).toBeInTheDocument();

    // The step bar goes back to a visited step; Next then returns to the review.
    fireEvent.click(screen.getByRole("button", { name: /Step 2 of 6: When/ }));
    expect(screen.getByRole("heading", { name: w.heading_when })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: w.backToReview }));

    fireEvent.click(screen.getByRole("button", { name: e.publish }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(onSubmit).toHaveBeenCalledTimes(1);
    expect(onSubmit.mock.calls[0][0]).toMatchObject({
      title: "Run up Lycabettus",
      location_id: null,
      place_name: "Lycabettus Hill",
      capacity: 20,
      price_cents: 1500,
      cohost_slugs: ["box-kypseli"],
    });
  });

  it("keeps the published event and lists the co-hosts the API could not ask", async () => {
    const onClose = vi.fn();
    const form: EventForm = { ...blankEventForm(LOCATIONS), title: "Partner WOD" };
    wrap(
      <EventWizard
        title="New event"
        initial={form}
        locations={LOCATIONS}
        cohosts={{ ownSlug: null }}
        onSubmit={vi.fn().mockResolvedValue({ cohostFailures: [{ slug: "other-box", code: "box_not_found" }] })}
        onClose={onClose}
      />,
    );
    for (let step = 0; step < 4; step += 1) fireEvent.click(next());
    const slug = screen.getByLabelText(w.cohostSlug);
    fireEvent.change(slug, { target: { value: "other-box" } });
    fireEvent.keyDown(slug, { key: "Enter" });
    fireEvent.click(next());
    fireEvent.click(screen.getByRole("button", { name: e.publish }));

    expect(await screen.findByRole("heading", { name: w.publishedTitle })).toBeInTheDocument();
    expect(screen.getByText("other-box")).toBeInTheDocument();
    expect(screen.getByText(e.err_box_not_found)).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: w.done }));
    expect(onClose).toHaveBeenCalled();
  });

  it("keeps a draft per host and offers it the next time", async () => {
    const props = {
      title: "New event",
      initial: blankEventForm(LOCATIONS),
      locations: LOCATIONS,
      draftKey: "club:1",
      onSubmit: vi.fn(),
      onClose: vi.fn(),
    };
    const first = wrap(<EventWizard {...props} />);
    fireEvent.change(screen.getByLabelText(e.fieldTitle), { target: { value: "Saturday WOD" } });
    await waitFor(() => expect(screen.getByText(w.draftSaved)).toBeInTheDocument());
    first.unmount();

    wrap(<EventWizard {...props} />);
    const offer = screen.getByRole("region", { name: w.draftFound });
    expect(offer).toHaveTextContent("Saturday WOD");
    await act(async () => fireEvent.click(within(offer).getByRole("button", { name: w.draftResume })));
    expect(screen.getByLabelText(e.fieldTitle)).toHaveValue("Saturday WOD");
  });

  it("sends no co-hosts for an event without any", async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined);
    wrap(
      <EventWizard
        title="Edit"
        initial={{ ...blankEventForm(LOCATIONS), title: "Partner WOD" }}
        editing={{ seriesId: null }}
        locations={LOCATIONS}
        cohosts={{ ownSlug: "box" }}
        onSubmit={onSubmit}
        onClose={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: e.save }));
    await waitFor(() => expect(onSubmit).toHaveBeenCalled());
    expect(onSubmit.mock.calls[0][0]).not.toHaveProperty("cohost_slugs");
  });

  it("opens an edit on the review, keeps the series scope, and jumps to a step from «Edit»", async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined);
    wrap(
      <EventWizard
        title="Edit"
        initial={{ ...blankEventForm(LOCATIONS), title: "Partner WOD" }}
        editing={{ seriesId: "series-1" }}
        locations={LOCATIONS}
        onSubmit={onSubmit}
        onClose={vi.fn()}
      />,
    );
    expect(screen.getByRole("heading", { name: w.heading_reviewEdit })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("radio", { name: e.scopeFollowing }));

    fireEvent.click(screen.getByRole("button", { name: "Edit: When" }));
    expect(screen.queryByText(e.fieldRepeat)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: w.backToReview }));
    fireEvent.click(screen.getByRole("button", { name: e.save }));
    await waitFor(() => expect(onSubmit).toHaveBeenCalled());
    expect(onSubmit.mock.calls[0][1]).toBe("following");
  });

  it("moves through a radiogroup with the arrow keys", () => {
    wrap(
      <EventWizard title="New event" initial={{ ...blankEventForm(LOCATIONS), title: "X" }} locations={LOCATIONS} startStep="who" editing={{ seriesId: null }} onSubmit={vi.fn()} onClose={vi.fn()} />,
    );
    const who = screen.getByRole("radiogroup", { name: e.fieldWho });
    const members = within(who).getByRole("radio", { name: new RegExp(e.membersOnly) });
    expect(members).toHaveAttribute("tabindex", "0");
    fireEvent.keyDown(members, { key: "ArrowRight" });
    expect(within(who).getByRole("radio", { name: new RegExp(e.openToAll) })).toHaveAttribute("aria-checked", "true");
  });
});
