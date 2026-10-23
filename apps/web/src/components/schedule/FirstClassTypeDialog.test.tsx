import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { FirstClassTypeDialog } from "./FirstClassTypeDialog";

const createClassType = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/api/schedule", () => ({
  createClassType: (...args: unknown[]) => createClassType(...args),
}));

describe("FirstClassTypeDialog", () => {
  it("creates the first class type and hands it back, so the class editor can open", async () => {
    const created = { id: "ct-1", name: "CrossFit", slug: "crossfit", sort_order: 0, archived_at: null };
    createClassType.mockResolvedValueOnce(created);
    const onCreated = vi.fn();

    render(<FirstClassTypeDialog token="tok" onClose={() => undefined} onCreated={onCreated} />);

    const create = screen.getByRole("button", { name: "firstClassTypeCreate" });
    expect(create).toBeDisabled();

    fireEvent.change(screen.getByRole("textbox"), { target: { value: "  CrossFit " } });
    fireEvent.click(create);

    await waitFor(() => expect(onCreated).toHaveBeenCalledWith(created));
    expect(createClassType).toHaveBeenCalledWith("tok", { name: "CrossFit" });
  });

  it("stays open and says why when the type can't be created", async () => {
    createClassType.mockRejectedValueOnce("offline");
    const onCreated = vi.fn();

    render(<FirstClassTypeDialog token="tok" onClose={() => undefined} onCreated={onCreated} />);
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "Open gym" } });
    fireEvent.click(screen.getByRole("button", { name: "firstClassTypeCreate" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("firstClassTypeFailed");
    expect(onCreated).not.toHaveBeenCalled();
  });
});
