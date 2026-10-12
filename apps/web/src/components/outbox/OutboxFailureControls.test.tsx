import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { OutboxFailureControls } from "@/components/outbox/OutboxFailureControls";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

describe("OutboxFailureControls", () => {
  it("shows the mapped reason and retries immediately", async () => {
    const onRetry = vi.fn();
    render(
      <OutboxFailureControls
        failure={{ category: "conflict", status: 409, code: "slot_full" }}
        onRetry={onRetry}
        onDiscard={vi.fn()}
      />,
    );

    expect(screen.getByText(/apiErrorSlotFull/)).toBeInTheDocument();
    expect(screen.getByText(/outboxConflictHint/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "outboxRetry" }));
    await waitFor(() => expect(onRetry).toHaveBeenCalledTimes(1));
  });

  it("requires confirmation before discarding", async () => {
    const onDiscard = vi.fn();
    render(
      <OutboxFailureControls
        failure={{ category: "permanent", status: 403 }}
        onRetry={vi.fn()}
        onDiscard={onDiscard}
        confirmKey="outboxDiscardMessageConfirm"
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "outboxDiscard" }));
    expect(onDiscard).not.toHaveBeenCalled();
    expect(screen.getByText("outboxDiscardMessageConfirm")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "outboxKeep" }));
    expect(screen.queryByText("outboxDiscardMessageConfirm")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "outboxDiscard" }));
    fireEvent.click(screen.getByRole("button", { name: "outboxDiscardConfirmAction" }));
    await waitFor(() => expect(onDiscard).toHaveBeenCalledTimes(1));
  });
});
