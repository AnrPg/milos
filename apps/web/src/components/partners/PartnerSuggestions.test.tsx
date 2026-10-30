import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { PartnerSuggestion } from "@/api/partners";

import { PartnerSuggestions } from "./PartnerSuggestions";

const fetchPartnerSuggestions = vi.fn();
const proposePartnerPlan = vi.fn();
const sendSuggestionFeedback = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${JSON.stringify(values)}` : key),
  useFormatter: () => ({
    dateTime: (date: Date) => date.toISOString().slice(0, 16),
    number: (value: number) => String(value),
  }),
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/api/partners", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/partners")>();
  return {
    ...actual,
    fetchPartnerSuggestions: (...args: unknown[]) => fetchPartnerSuggestions(...args),
    proposePartnerPlan: (...args: unknown[]) => proposePartnerPlan(...args),
    sendSuggestionFeedback: (...args: unknown[]) => sendSuggestionFeedback(...args),
  };
});

const suggestion = (patch: Partial<PartnerSuggestion>): PartnerSuggestion => ({
  id: "e1",
  key: "event:e1",
  kind: "event",
  title: "Run club",
  place: "Pedion tou Areos",
  starts_at: "2026-11-01T08:00:00Z",
  time_zone: "Europe/Athens",
  distances_km: [2.1, 3],
  reasons: ["shared_time:weekend", "near_both"],
  booked_by_me: false,
  booked_by_partner: false,
  ...patch,
});

function renderIdeas(onProposed = vi.fn()) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const view = render(
    <QueryClientProvider client={client}>
      <PartnerSuggestions matchId="m1" name="Dimitra" onProposed={onProposed} />
    </QueryClientProvider>,
  );
  return { ...view, onProposed };
}

describe("PartnerSuggestions (ADR-280 §4, mockup decision 4 A)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("shows nothing when there are no ideas («Πάμε μαζί;» stays elsewhere)", async () => {
    fetchPartnerSuggestions.mockResolvedValue([]);
    const { container } = renderIdeas();
    await waitFor(() => expect(fetchPartnerSuggestions).toHaveBeenCalledWith("token", "m1"));
    expect(container).toBeEmptyDOMElement();
  });

  it("lists at most three ideas near you both, each with its reasons in plain words", async () => {
    fetchPartnerSuggestions.mockResolvedValue([
      suggestion({}),
      suggestion({ id: "t1", key: "trial:t1", kind: "trial", title: "CrossFit Patisia", reasons: ["one_booked", "level_fit"], booked_by_partner: true }),
      suggestion({ id: "e2", key: "event:e2" }),
      suggestion({ id: "e3", key: "event:e3" }),
    ]);
    renderIdeas();
    expect(await screen.findByText("ideasNearBoth")).toBeInTheDocument();
    expect(screen.getAllByTestId("partner-suggestion")).toHaveLength(3);
    const reasons = screen.getAllByTestId("partner-suggestion-reasons").map((node) => node.textContent);
    expect(reasons[0]).toBe('reason_shared_time:{"time":"time_weekend"} · reason_distances:{"mine":"2.1","theirs":"3"}');
    expect(reasons[1]).toBe('reason_partner_booked:{"name":"Dimitra"} · reason_level_fit');
  });

  it("says when the classes come from a box you share", async () => {
    fetchPartnerSuggestions.mockResolvedValue([suggestion({ id: "c1", key: "class:c1", kind: "class", distances_km: [null, null], reasons: ["shared_time:early"] })]);
    renderIdeas();
    expect(await screen.findByText("ideasSharedBox")).toBeInTheDocument();
  });

  it("«Πρότεινε» posts the idea as a plan", async () => {
    fetchPartnerSuggestions.mockResolvedValue([suggestion({})]);
    proposePartnerPlan.mockResolvedValue({ id: "msg-1" });
    const { onProposed } = renderIdeas();
    fireEvent.click(await screen.findByRole("button", { name: "propose" }));
    await waitFor(() => expect(proposePartnerPlan).toHaveBeenCalledWith("token", "m1", { kind: "event", id: "e1" }));
    await waitFor(() => expect(onProposed).toHaveBeenCalled());
  });

  it("«Δεν ταιριάζει» asks why, sends it and takes the idea away", async () => {
    fetchPartnerSuggestions.mockResolvedValue([suggestion({})]);
    sendSuggestionFeedback.mockResolvedValue({ key: "event:e1", reason: "bad_time" });
    const { container } = renderIdeas();
    fireEvent.click(await screen.findByRole("button", { name: "notForUs" }));
    fireEvent.click(screen.getByRole("button", { name: "feedback_bad_time" }));
    await waitFor(() => expect(sendSuggestionFeedback).toHaveBeenCalledWith("token", "m1", "event:e1", "bad_time"));
    expect(container).toBeEmptyDOMElement();
  });
});
