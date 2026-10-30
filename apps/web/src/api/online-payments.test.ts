import { describe, expect, it } from "vitest";

import {
  connectOutcome,
  connectsWithOneButton,
  declineReason,
  isConnected,
  pickableProviders,
  type PaymentAccountStatus,
} from "./online-payments";

const status = (extra: Partial<PaymentAccountStatus> = {}): PaymentAccountStatus => ({
  account: null,
  providers: ["stripe", "viva"],
  environments: ["test", "live"],
  connect_providers: { live: ["stripe"], test: [] },
  ...extra,
});

describe("online payments helpers", () => {
  it("offers Viva first and one-button connect only where the API lists it", () => {
    expect(pickableProviders(status())).toEqual(["viva", "stripe"]);
    expect(connectsWithOneButton(status(), "stripe")).toBe(true);
    expect(connectsWithOneButton(status(), "viva")).toBe(false);
    expect(connectsWithOneButton(status(), "stripe", "test")).toBe(false);
  });

  it("counts only an active account as connected", () => {
    expect(isConnected(status())).toBe(false);
    const account = { status: "disabled" } as PaymentAccountStatus["account"];
    expect(isConnected(status({ account }))).toBe(false);
    expect(isConnected(status({ account: { ...account!, status: "active" } }))).toBe(true);
  });

  it("groups provider decline codes by what the member has to do", () => {
    expect(declineReason("insufficient_funds")).toBe("insufficient_funds");
    expect(declineReason("10051")).toBe("insufficient_funds");
    expect(declineReason("expired_card")).toBe("expired_card");
    expect(declineReason("authentication_required")).toBe("authentication");
    expect(declineReason("payment_method_not_found")).toBe("no_card");
    expect(declineReason("do_not_honor")).toBe("declined");
    expect(declineReason(null)).toBe("declined");
  });

  it("reads the connect codes the callback sends back", () => {
    expect(connectOutcome(null)).toBeNull();
    expect(connectOutcome("ok")).toBe("ok");
    expect(connectOutcome("access_denied")).toBe("access_denied");
    expect(connectOutcome("connect_state_invalid")).toBe("connect_state_invalid");
    expect(connectOutcome("payment_provider_unavailable")).toBe("unavailable");
    expect(connectOutcome("something_new")).toBe("failed");
  });
});
