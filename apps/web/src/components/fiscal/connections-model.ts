// ADR-273, mockup p3 (alternative A): what the «Συνδέσεις» card and its
// side panel need to know about each fiscal connection, kept free of React
// so it can be tested on its own. Brand names stay here, never in messages.

import type {
  AuthorityConnection,
  ConnectionCheck,
  ConnectionKind,
  FiscalConnection,
  PeppolConnection,
  RegistryConnection,
  TillConnection,
} from "@/api/fiscal";

export const CONNECTION_KINDS = ["mydata", "registry", "tse", "rksv", "sign_fr", "peppol"] as const satisfies readonly ConnectionKind[];

/** The provider's own name for a connection; the registry's is a translated term. */
export const CONNECTION_BRANDS: Record<ConnectionKind, string | null> = {
  mydata: "myDATA",
  registry: null,
  tse: "fiskaly SIGN DE",
  rksv: "fiskaly SIGN AT",
  sign_fr: "fiskaly SIGN FR",
  peppol: "fiskaly E-INVOICE",
};

/** Who answers for the connection: AADE or fiskaly (its refusals read differently). */
export type Provider = "aade" | "fiskaly";
export const PROVIDER_OF: Record<ConnectionKind, Provider> = {
  mydata: "aade",
  registry: "aade",
  tse: "fiskaly",
  rksv: "fiskaly",
  sign_fr: "fiskaly",
  peppol: "fiskaly",
};

/** The till device each fiskaly SIGN connection sets up, as the law names it. */
export const DEVICE_NAMES: Partial<Record<ConnectionKind, string>> = { tse: "TSE", rksv: "RKSV", sign_fr: "SIGN FR" };

/** A row's monogram on the card (mockup p3). */
export const CONNECTION_MARKS: Record<ConnectionKind, string> = {
  mydata: "my",
  registry: "Μ",
  tse: "f",
  rksv: "f",
  sign_fr: "f",
  peppol: "f",
};

export type RowStatus = "none" | "active" | "invalid" | "provisioning";

export function rowStatus(connection: FiscalConnection | null | undefined): RowStatus {
  if (!connection) return "none";
  return connection.status === "active" || connection.status === "invalid" || connection.status === "provisioning"
    ? connection.status
    : "invalid";
}

// --- The form -------------------------------------------------------------

export type TextField = "user_id" | "username" | "legal_entity_id" | "peppol_id";
export type SecretField = "subscription_key" | "password" | "api_key" | "api_secret";
export type FormField = TextField | SecretField | "environment";

export type FormShape = {
  /** Plain fields, shown first. */
  text: TextField[];
  secrets: SecretField[];
  /** Plain fields kept under «Προχωρημένα». */
  advancedText: TextField[];
};

export const FORM_SHAPES: Record<ConnectionKind, FormShape> = {
  mydata: { text: ["user_id"], secrets: ["subscription_key"], advancedText: [] },
  registry: { text: ["username"], secrets: ["password"], advancedText: [] },
  tse: { text: [], secrets: ["api_key", "api_secret"], advancedText: [] },
  rksv: { text: [], secrets: ["api_key", "api_secret"], advancedText: [] },
  sign_fr: { text: [], secrets: ["api_key", "api_secret"], advancedText: [] },
  peppol: { text: ["legal_entity_id"], secrets: ["api_key", "api_secret"], advancedText: ["peppol_id"] },
};

export function formFields(kind: ConnectionKind): FormField[] {
  const shape = FORM_SHAPES[kind];
  return [...shape.text, ...shape.secrets, ...shape.advancedText, "environment"];
}

/** «Παραγωγή» or «Δοκιμή»: the owner sees two, the API knows three (ADR-273). */
export type EnvironmentChoice = "production" | "test";

export function environmentChoice(environment: string | null | undefined): EnvironmentChoice {
  return environment === "test" || environment === "sandbox" ? "test" : "production";
}

export type Draft = Partial<Record<TextField | SecretField, string>> & { environment: EnvironmentChoice };

export function draftOf(kind: ConnectionKind, connection: FiscalConnection | null): Draft {
  const draft: Draft = { environment: environmentChoice(connection?.environment) };
  if (!connection) return draft;
  if (kind === "mydata") draft.user_id = (connection as AuthorityConnection).user_id ?? "";
  if (kind === "registry") draft.username = (connection as RegistryConnection).username ?? "";
  if (kind === "peppol") {
    const peppol = connection as PeppolConnection;
    draft.legal_entity_id = peppol.legal_entity_id ?? "";
    draft.peppol_id = peppol.peppol_id ?? "";
  }
  return draft;
}

/** Whether a secret is already saved: the form then shows «Αποθηκευμένο». */
export function hasSecret(kind: ConnectionKind, connection: FiscalConnection | null, field: SecretField): boolean {
  if (!connection) return false;
  switch (field) {
    case "subscription_key":
      return kind === "mydata" && Boolean((connection as AuthorityConnection).has_subscription_key);
    case "password":
      return kind === "registry" && Boolean((connection as RegistryConnection).has_password);
    case "api_key":
      return Boolean((connection as TillConnection | PeppolConnection).has_api_key);
    case "api_secret":
      return Boolean((connection as TillConnection | PeppolConnection).has_api_secret);
  }
}

/**
 * The API's environment for «Δοκιμή»: AADE's registry only has a sandbox; the
 * others use the provider's test system once credentials are given, and the
 * sandbox (made-up answers, no credentials) before that.
 */
export function apiEnvironment(kind: ConnectionKind, draft: Draft, connection: FiscalConnection | null): string {
  if (draft.environment === "production") return "production";
  if (kind === "registry") return "sandbox";
  const shape = FORM_SHAPES[kind];
  const credentials =
    shape.secrets.some((field) => Boolean(draft[field]?.trim()) || hasSecret(kind, connection, field)) ||
    shape.text.some((field) => Boolean(draft[field]?.trim()));
  return credentials ? "test" : "sandbox";
}

export type SaveBody = Record<string, string | boolean | null>;

/** What «Αποθήκευση» sends: secrets only when typed, so saved ones are kept. */
export function saveBody(kind: ConnectionKind, draft: Draft, connection: FiscalConnection | null, reprovision = false): SaveBody {
  const shape = FORM_SHAPES[kind];
  const body: SaveBody = { environment: apiEnvironment(kind, draft, connection) };
  for (const field of [...shape.text, ...shape.advancedText]) {
    const value = draft[field]?.trim() ?? "";
    if (field === "username") {
      if (value) body[field] = value;
    } else {
      body[field] = value || null;
    }
  }
  for (const field of shape.secrets) {
    const value = draft[field]?.trim();
    if (value) body[field] = value;
  }
  if (reprovision) body.reprovision = true;
  return body;
}

// --- Check results and error codes -----------------------------------------

export const ERROR_CODES = [
  "credentials_rejected",
  "credentials_missing",
  "unit_not_found",
  "unit_not_ready",
  "system_not_found",
  "tax_id_missing",
  "tax_id_not_found",
  "siren_missing",
  "limit_reached",
  "unreachable",
  "provisioning_failed",
  "provider_retired",
] as const;
export type ErrorCode = (typeof ERROR_CODES)[number];

export function knownErrorCode(code: string | null | undefined): ErrorCode | null {
  return code && (ERROR_CODES as readonly string[]).includes(code) ? (code as ErrorCode) : null;
}

/** The field an error code belongs under, or null for the form-level notice. */
export function errorField(kind: ConnectionKind, code: ErrorCode): FormField | null {
  switch (code) {
    case "credentials_rejected":
    case "credentials_missing":
      return FORM_SHAPES[kind].secrets[0] ?? null;
    case "system_not_found":
      return kind === "peppol" ? "legal_entity_id" : null;
    default:
      return null;
  }
}

/** API error codes a save or a check can answer with, shown in the form's words. */
export const SAVE_ERROR_CODES = [
  "till_credentials_refused",
  "till_provisioning_failed",
  "siren_missing",
  "invalid_peppol_id",
  "fiscal_connections_managed_by_palee",
  "check_too_soon",
  "connection_not_found",
] as const;
export type SaveErrorCode = (typeof SAVE_ERROR_CODES)[number];

export function knownSaveError(code: string | null | undefined): SaveErrorCode | null {
  return code && (SAVE_ERROR_CODES as readonly string[]).includes(code) ? (code as SaveErrorCode) : null;
}

/** Where a save error belongs: a field, or the form-level notice. */
export function saveErrorField(kind: ConnectionKind, code: SaveErrorCode): FormField | null {
  if (code === "till_credentials_refused") return FORM_SHAPES[kind].secrets[0] ?? null;
  if (code === "invalid_peppol_id") return "peppol_id";
  return null;
}

export type CheckOutcome = { kind: "ok"; registry: { taxId: string; name: string | null } | null } | { kind: "invalid"; code: ErrorCode | null } | { kind: "unreachable" };

export function checkOutcome(check: ConnectionCheck | null | undefined): CheckOutcome | null {
  if (!check) return null;
  if (check.result === "ok") {
    const taxId = check.detail?.tax_id;
    return { kind: "ok", registry: taxId ? { taxId, name: check.detail?.legal_name ?? null } : null };
  }
  if (check.result === "invalid") return { kind: "invalid", code: knownErrorCode(check.error_code) };
  return { kind: "unreachable" };
}

/** Whether the panel opened from a link (`?connection=mydata`, a notification) names a row of this box. */
export function requestedKind(value: string | null | undefined, kinds: readonly string[]): ConnectionKind | null {
  return value && kinds.includes(value) && (CONNECTION_KINDS as readonly string[]).includes(value) ? (value as ConnectionKind) : null;
}
