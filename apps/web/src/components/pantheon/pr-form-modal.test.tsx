import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { PRRecord } from "@/api/gamification";

const { createPR, editPR, updatePR } = vi.hoisted(() => ({
  createPR: vi.fn(),
  editPR: vi.fn(),
  updatePR: vi.fn(),
}));

vi.mock("@/api/gamification", async (importOriginal) => {
  const original = await importOriginal<typeof import("@/api/gamification")>();
  return { ...original, createPR, editPR, updatePR };
});

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access-token" } }),
}));

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

import { PRFormModal } from "@/components/pantheon/PRFormModal";

const pr: PRRecord = {
  id: "pr-1",
  user_id: "user-1",
  name: "Back squat",
  current_score: 100,
  unit: "kg",
  higher_is_better: true,
  beaten_on: "2026-07-01",
  supporting_metrics: {},
  notes: null,
  inserted_at: "2026-07-01T10:00:00Z",
  updated_at: "2026-07-01T10:00:00Z",
};

function renderModal() {
  const queryClient = new QueryClient({
    defaultOptions: { mutations: { retry: false }, queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <PRFormModal pr={pr} onClose={vi.fn()} />
    </QueryClientProvider>,
  );
}

function renderNewModal(defaultGymSlug: string) {
  const queryClient = new QueryClient({
    defaultOptions: { mutations: { retry: false }, queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <PRFormModal
        pr={null}
        gyms={[{ slug: "atlas-gym", name: "Atlas Gym" }]}
        defaultGymSlug={defaultGymSlug}
        onClose={vi.fn()}
      />
    </QueryClientProvider>,
  );
}

describe("PRFormModal", () => {
  beforeEach(() => {
    createPR.mockReset().mockResolvedValue(pr);
    editPR.mockReset().mockResolvedValue(pr);
    updatePR.mockReset().mockResolvedValue(pr);
  });

  it("applies edits without creating a historical result", async () => {
    renderModal();

    fireEvent.click(screen.getByRole("button", { name: "applyPrEdits" }));

    await waitFor(() => expect(editPR).toHaveBeenCalledOnce());
    expect(updatePR).not.toHaveBeenCalled();
  });

  it("records a new result when a better PR is submitted", async () => {
    renderModal();

    fireEvent.click(screen.getByRole("button", { name: "recordBetterPr" }));

    await waitFor(() => expect(updatePR).toHaveBeenCalledOnce());
    expect(editPR).not.toHaveBeenCalled();
  });

  it("records a new PR in the default gym so that gym's coaches can see it", async () => {
    renderNewModal("atlas-gym");

    fireEvent.change(screen.getByPlaceholderText("eGBackSquat1rm675304b"), { target: { value: "Clean" } });
    fireEvent.change(screen.getByRole("spinbutton"), { target: { value: "90" } });
    fireEvent.click(screen.getByRole("button", { name: "addPr24c8c6f" }));

    await waitFor(() => expect(createPR).toHaveBeenCalledOnce());
    expect(createPR.mock.calls[0][1]).toMatchObject({ name: "Clean", organization_slug: "atlas-gym" });
  });

  it("records a personal PR when no gym is chosen", async () => {
    renderNewModal("atlas-gym");

    fireEvent.change(screen.getByRole("combobox", { name: "gymLabel" }), { target: { value: "" } });
    fireEvent.change(screen.getByPlaceholderText("eGBackSquat1rm675304b"), { target: { value: "Marathon" } });
    fireEvent.change(screen.getByRole("spinbutton"), { target: { value: "42" } });
    fireEvent.click(screen.getByRole("button", { name: "addPr24c8c6f" }));

    await waitFor(() => expect(createPR).toHaveBeenCalledOnce());
    expect(createPR.mock.calls[0][1]).toMatchObject({ name: "Marathon", organization_slug: null });
  });

  it("bounds the popup to the viewport and lets its contents scroll", () => {
    renderModal();

    expect(screen.getByRole("dialog")).toHaveClass("max-h-[calc(100dvh-1rem)]", "overflow-y-auto");
  });
});
