import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import messages from "../../../messages/en.json";
import { RefundReceiptDocumentDialog } from "@/components/finance/RefundReceiptDocumentDialog";

function renderDialog(onClose = vi.fn()) {
  render(
    <NextIntlClientProvider locale="en" messages={messages}>
      <RefundReceiptDocumentDialog html="<p>receipt</p>" onClose={onClose} receiptNumber="RFD-000007" />
    </NextIntlClientProvider>,
  );
  return onClose;
}

describe("RefundReceiptDocumentDialog", () => {
  it("previews the server document in a fully sandboxed frame", () => {
    renderDialog();

    const frame = screen.getByTitle("Refund receipt RFD-000007");
    expect(frame.getAttribute("sandbox")).toBe("");
    expect(frame.getAttribute("srcdoc")).toBe("<p>receipt</p>");
  });

  it("opens a printable copy in a new tab and closes", () => {
    const open = vi.spyOn(window, "open").mockReturnValue(null);
    const createObjectURL = vi.fn(() => "blob:receipt");
    Object.defineProperty(URL, "createObjectURL", { configurable: true, value: createObjectURL });
    Object.defineProperty(URL, "revokeObjectURL", { configurable: true, value: vi.fn() });
    const onClose = renderDialog();

    fireEvent.click(screen.getByRole("button", { name: "Open printable receipt" }));
    expect(createObjectURL).toHaveBeenCalledTimes(1);
    expect(open).toHaveBeenCalledWith("blob:receipt", "_blank", "noopener");

    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalledTimes(1);
    open.mockRestore();
  });
});
