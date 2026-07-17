import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { PRRecord } from "@/api/gamification";

const { editPR, updatePR } = vi.hoisted(() => ({
  editPR: vi.fn(),
  updatePR: vi.fn(),
}));

vi.mock("@/api/gamification", async (importOriginal) => {
  const original = await importOriginal<typeof import("@/api/gamification")>();
  return { ...original, editPR, updatePR };
});

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

describe("PRFormModal", () => {
  beforeEach(() => {
    editPR.mockReset().mockResolvedValue(pr);
    updatePR.mockReset().mockResolvedValue(pr);
  });

  it("keeps update and in-place edit as separate popup actions", async () => {
    renderModal();

    fireEvent.click(screen.getByRole("button", { name: "edit5301648" }));

    await waitFor(() => expect(editPR).toHaveBeenCalledOnce());
    expect(updatePR).not.toHaveBeenCalled();
  });

  it("records a new result when Update is clicked", async () => {
    renderModal();

    fireEvent.click(screen.getByRole("button", { name: "updatePr71b8cf3" }));

    await waitFor(() => expect(updatePR).toHaveBeenCalledOnce());
    expect(editPR).not.toHaveBeenCalled();
  });

  it("bounds the popup to the viewport and lets its contents scroll", () => {
    renderModal();

    expect(screen.getByRole("dialog")).toHaveClass("max-h-[calc(100dvh-1rem)]", "overflow-y-auto");
  });
});
