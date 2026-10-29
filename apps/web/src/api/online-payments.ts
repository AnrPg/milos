import { apiRequest } from "@/api/client";

/*
 * Online payments for staff (ADR-246/247/260/261): the business's own Viva
 * or Stripe account in Ρυθμίσεις › Πληρωμές, and the saved-card charges that
 * need a person in Οικονομικά › Ουρές. Calls go through the selected gym
 * (`/org/:slug/admin/payments/...`). Wire shapes follow
 * `PaleeWeb.Schemas.Payments` (see `generated/schema.ts`). Credentials are
 * written, never read back: `credentials_set` names the saved ones.
 */

export type PaymentProvider = "sandbox" | "viva" | "stripe";
export type PaymentEnvironment = "test" | "live";

/** What members may pay online (ADR-260); every one is on by default. */
export type PaymentPurposes = {
  packages: boolean;
  autopay: boolean;
  drop_in: boolean;
  shop: boolean;
  personal_training: boolean;
};

export type PaymentOptions = {
  purposes: PaymentPurposes;
  notify_member: boolean;
  notify_staff: boolean;
};

export type PaymentAccount = {
  id: string;
  provider: PaymentProvider;
  environment: PaymentEnvironment;
  /** "active" or "disabled" (after «Αποσύνδεση»). */
  status: string;
  settings: Record<string, string>;
  credentials_set: string[];
  last_error?: string | null;
  checked_at?: string | null;
  updated_at?: string | null;
  webhook_url: string;
  options: PaymentOptions;
  /** "platform": connected with one button (ADR-261); "keys": pasted API keys (ADR-246). */
  connection: "keys" | "platform";
};

export type PaymentAccountStatus = {
  account: PaymentAccount | null;
  providers: string[];
  environments: string[];
  /** Providers that connect with one button, per environment (ADR-261). */
  connect_providers: Record<string, string[]>;
};

export type FailedCharge = {
  id: string;
  user_id?: string | null;
  member_name: string | null;
  purpose_type: string;
  amount_cents: number;
  currency: string;
  description: string;
  status: "scheduled" | "awaiting_payer" | "processing" | "succeeded" | "failed" | "cancelled" | "expired";
  failure_code?: string | null;
  next_attempt_at?: string | null;
  /** Declines so far. */
  declines: number;
  /** Retries the schedule allows (1, 3 and 7 days: 3). */
  retries: number;
};

export type PaymentAccountUpdate = {
  provider: PaymentProvider;
  environment: PaymentEnvironment;
  credentials?: Partial<Record<CredentialKey, string>>;
  settings?: { source_code?: string };
};

export type PaymentOptionsUpdate = {
  purposes?: Partial<PaymentPurposes>;
  notify_member?: boolean;
  notify_staff?: boolean;
};

export type CredentialKey = "client_id" | "client_secret" | "merchant_id" | "api_key" | "secret_key" | "webhook_secret";

/** The keys each provider asks for (`credential_keys/0` of its gateway). */
export const PROVIDER_CREDENTIALS: Record<PaymentProvider, CredentialKey[]> = {
  viva: ["merchant_id", "api_key", "client_id", "client_secret"],
  stripe: ["secret_key", "webhook_secret"],
  sandbox: [],
};

/** The order of the switches under «Αλλαγή» (the mockup's ONLINE list). */
export const PURPOSE_KEYS: Array<keyof PaymentPurposes> = ["packages", "autopay", "drop_in", "shop", "personal_training"];

/** Recommended in Europe; the first one offered. */
export const DEFAULT_PROVIDER: PaymentProvider = "viva";

export const DEFAULT_OPTIONS: PaymentOptions = {
  purposes: { packages: true, autopay: true, drop_in: true, shop: true, personal_training: true },
  notify_member: true,
  notify_staff: true,
};

export function fetchPaymentAccount(token: string) {
  return apiRequest<PaymentAccountStatus>("/admin/payments/account", { token });
}

/** ADR-261: the provider page to send the owner to; it comes back to Settings with `connect=ok|<code>`. */
export function startPaymentConnect(token: string, provider: PaymentProvider, environment: PaymentEnvironment = "live") {
  return apiRequest<{ url: string }>("/admin/payments/connect", {
    method: "POST",
    token,
    body: { provider, environment },
  });
}

export function savePaymentAccount(token: string, update: PaymentAccountUpdate) {
  return apiRequest<PaymentAccountStatus>("/admin/payments/account", { method: "PUT", token, body: update });
}

export function savePaymentOptions(token: string, update: PaymentOptionsUpdate) {
  return apiRequest<PaymentAccountStatus>("/admin/payments/account/options", { method: "PUT", token, body: update });
}

export function disconnectPaymentAccount(token: string) {
  return apiRequest<PaymentAccountStatus>("/admin/payments/account", { method: "DELETE", token });
}

export function fetchFailedCharges(token: string) {
  return apiRequest<{ payments: FailedCharge[]; total: number }>("/admin/payments/attention", { token });
}

export type FailedChargeAction = "retry-charge" | "card-link" | "dismiss";

export function actOnFailedCharge(token: string, id: string, action: FailedChargeAction) {
  return apiRequest<{ payment: FailedCharge }>(`/admin/payments/${encodeURIComponent(id)}/${action}`, {
    method: "POST",
    token,
  });
}

/** Whether online payments work now (an active account). */
export function isConnected(status: PaymentAccountStatus | null | undefined): boolean {
  return status?.account?.status === "active";
}

/** Providers a business can pick, best first (Viva is recommended in Europe). */
export function pickableProviders(status: PaymentAccountStatus | null | undefined): PaymentProvider[] {
  const offered = new Set(status?.providers ?? []);
  return (["viva", "stripe", "sandbox"] as const).filter((provider) => offered.has(provider));
}

/** Whether a provider connects with one button in this environment. */
export function connectsWithOneButton(
  status: PaymentAccountStatus | null | undefined,
  provider: PaymentProvider,
  environment: PaymentEnvironment = "live",
): boolean {
  return (status?.connect_providers?.[environment] ?? []).includes(provider);
}

export function providerName(provider: string | null | undefined): string {
  if (provider === "stripe") return "Stripe";
  if (provider === "sandbox") return "Sandbox";
  return "Viva";
}

/** Failure codes of providers, grouped by what the member has to do. */
export type DeclineReason = "insufficient_funds" | "expired_card" | "authentication" | "no_card" | "declined";

export function declineReason(code: string | null | undefined): DeclineReason {
  const value = (code ?? "").toLowerCase();
  // Stripe decline codes; Viva answers ISO 8583 response codes (51, 54, 65, 1A) prefixed 100.
  if (["insufficient_funds", "10051", "51"].includes(value)) return "insufficient_funds";
  if (["expired_card", "10054", "54"].includes(value)) return "expired_card";
  if (["authentication_required", "10065", "65", "1a", "card_authentication_required"].includes(value)) return "authentication";
  if (value === "payment_method_not_found") return "no_card";
  return "declined";
}

/** The `connect=` codes the callback sends back, as the message to show. */
export type ConnectOutcome =
  | "ok"
  | "access_denied"
  | "invalid_grant"
  | "connect_state_invalid"
  | "rejected"
  | "environment_mismatch"
  | "forbidden"
  | "unavailable"
  | "failed";

export function connectOutcome(code: string | null | undefined): ConnectOutcome | null {
  if (!code) return null;
  switch (code) {
    case "ok":
    case "access_denied":
    case "invalid_grant":
    case "connect_state_invalid":
    case "rejected":
    case "environment_mismatch":
    case "forbidden":
      return code;
    case "payment_provider_unavailable":
      return "unavailable";
    case "payment_provider_rejected_credentials":
      return "rejected";
    default:
      return "failed";
  }
}
