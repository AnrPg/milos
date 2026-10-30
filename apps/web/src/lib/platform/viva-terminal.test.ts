import { describe, expect, it, vi } from "vitest";

import {
  buildSaleUrl,
  launchTerminalSale,
  parseTerminalCallback,
  takePendingTerminalResult,
  type PaleeVivaTerminalPlugin,
} from "./viva-terminal";

// ADR-249: the request handed to the «Viva.com Terminal» app and its answer.
const request = {
  scheme: "vivapayclient://pay/v1",
  params: {
    appId: "app.palee.member",
    action: "sale",
    clientTransactionId: "pt1.6a0d1f0e-0000-4000-8000-000000000001.sig_-x",
    amount: "1200",
    customerTrns: "Πακέτο 8 & (μήνας)",
    callback: "palee-terminal://result",
    paymentMethod: "CardPresent",
    show_receipt: "false",
  },
};

describe("buildSaleUrl", () => {
  it("builds Viva's Sale request with every parameter percent-encoded", () => {
    const url = buildSaleUrl(request);
    expect(url.startsWith("vivapayclient://pay/v1?appId=app.palee.member&action=sale&")).toBe(true);
    expect(url).toContain("&amount=1200&");
    expect(url).toContain("callback=palee-terminal%3A%2F%2Fresult");
    expect(url).not.toContain(" ");
    expect(url).not.toContain("(");
    const query = new URLSearchParams(url.split("?")[1]);
    expect(query.get("customerTrns")).toBe("Πακέτο 8 & (μήνας)");
    expect(query.get("clientTransactionId")).toBe(request.params.clientTransactionId);
  });

  it("drops empty parameters and refuses any other scheme", () => {
    expect(buildSaleUrl({ scheme: "vivapayclient://pay/v1", params: { action: "sale", tipAmount: "" } })).toBe(
      "vivapayclient://pay/v1?action=sale",
    );
    expect(() => buildSaleUrl({ scheme: "https://evil.example/pay", params: {} })).toThrow("terminal_scheme_not_allowed");
  });
});

describe("parseTerminalCallback", () => {
  it("reads an approved sale as Viva sends it (spaces and + unencoded)", () => {
    const url =
      "palee-terminal://result?status=success&message=Transaction successful&action=sale&clientTransactionId=pt1.abc.sig" +
      "&amount=1200&transactionId=a12e1ba8-6153-7754-a6a8-e3d2654872c8&verificationMethod=CONTACTLESS - NO CVM" +
      "&accountNumber=515876******4490&fiscalisationSigningDetails=ab+cd/ef==";
    const parsed = parseTerminalCallback(url);
    expect(parsed?.body).toEqual({
      reference: "pt1.abc.sig",
      status: "success",
      transaction_id: "a12e1ba8-6153-7754-a6a8-e3d2654872c8",
      message: "Transaction successful",
    });
    expect(parsed?.params.fiscalisationSigningDetails).toBe("ab+cd/ef==");
    expect(parsed?.params.verificationMethod).toBe("CONTACTLESS - NO CVM");
  });

  it("reads a decline, keeping its transaction for the server to confirm", () => {
    const url =
      "palee-terminal://result?status=fail&message=(-12)%20TRANSACTION_DECLINED_BY_SERVER&clientTransactionId=pt1.abc.sig" +
      "&transactionId=3ca278e7-0679-411e-8279-ebb29ee519b2";
    expect(parseTerminalCallback(url)?.body).toEqual({
      reference: "pt1.abc.sig",
      status: "fail",
      transaction_id: "3ca278e7-0679-411e-8279-ebb29ee519b2",
      message: "(-12) TRANSACTION_DECLINED_BY_SERVER",
    });
  });

  it("gives no body without a request, and ignores other links", () => {
    expect(parseTerminalCallback("palee-terminal://result?status=fail")?.body).toBeNull();
    expect(parseTerminalCallback("palee-terminal://result/?clientTransactionId=x&transactionId=")?.body).toEqual({
      reference: "x",
      status: "error",
      transaction_id: null,
      message: null,
    });
    expect(parseTerminalCallback("https://palee.app/c/x?clientTransactionId=x")).toBeNull();
    expect(parseTerminalCallback("palee-terminal://other?clientTransactionId=x")).toBeNull();
  });

  it("keeps the first of repeated parameters and survives bad encoding", () => {
    const parsed = parseTerminalCallback("palee-terminal://result?clientTransactionId=a&clientTransactionId=b&message=100%");
    expect(parsed?.body?.reference).toBe("a");
    expect(parsed?.body?.message).toBe("100%");
  });
});

describe("the plugin wrapper", () => {
  function plugin(overrides: Partial<PaleeVivaTerminalPlugin> = {}): PaleeVivaTerminalPlugin {
    return {
      isAvailable: vi.fn(async () => ({ available: true })),
      pay: vi.fn(async () => ({ launched: true })),
      takePendingResult: vi.fn(async () => ({ url: null })),
      addListener: vi.fn(async () => ({ remove: async () => undefined })),
      ...overrides,
    };
  }

  it("hands the API's request to the native plugin", async () => {
    const native = plugin();
    await launchTerminalSale(request, native);
    expect(native.pay).toHaveBeenCalledWith({ scheme: request.scheme, params: request.params });
  });

  it("fails when the terminal app is missing, and never opens a foreign scheme", async () => {
    await expect(launchTerminalSale(request, plugin({ pay: vi.fn(async () => ({ launched: false })) }))).rejects.toThrow(
      "terminal_app_unavailable",
    );
    const native = plugin();
    await expect(launchTerminalSale({ scheme: "tel:123", params: {} }, native)).rejects.toThrow("terminal_scheme_not_allowed");
    expect(native.pay).not.toHaveBeenCalled();
  });

  it("returns a callback that arrived while nobody listened", async () => {
    const native = plugin({
      takePendingResult: vi.fn(async () => ({ url: "palee-terminal://result?status=success&clientTransactionId=r&transactionId=t" })),
    });
    expect((await takePendingTerminalResult(native))?.body).toEqual({
      reference: "r",
      status: "success",
      transaction_id: "t",
      message: null,
    });
    expect(await takePendingTerminalResult(plugin())).toBeNull();
  });
});
