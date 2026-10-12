import { ApiError } from "@/api/client";
import { localizeError, type UiTranslator } from "@/i18n/presentation";

/**
 * Retry classification for durable outbox operations (ADR-067, ADR-120).
 *
 * - `transient`: network failures, expired sessions, throttling, and server
 *   errors. The operation stays pending and is replayed automatically with the
 *   same idempotency key.
 * - `permanent`: authorization or validation failures. Never replayed
 *   automatically; the user decides to retry or discard.
 * - `conflict`: the server state moved on (409). Never replayed automatically;
 *   surfaced so the user can review the latest data first.
 */
export type OutboxRetryClass = "transient" | "permanent" | "conflict";

export type OutboxFailure = {
  category: OutboxRetryClass;
  status?: number;
  code?: string;
};

const TRANSIENT_STATUSES = new Set([401, 408, 425, 429]);

export function classifyDeliveryError(
  error: unknown,
  overrides: { conflictCodes?: readonly string[]; permanentCodes?: readonly string[] } = {},
): OutboxFailure {
  if (!(error instanceof ApiError)) return { category: "transient" };

  const { status } = error;
  const code = error.payload?.code;
  const failure = (category: OutboxRetryClass): OutboxFailure =>
    code ? { category, status, code } : { category, status };

  if (code && overrides.conflictCodes?.includes(code)) return failure("conflict");
  if (code && overrides.permanentCodes?.includes(code)) return failure("permanent");
  if (status >= 500 || TRANSIENT_STATUSES.has(status)) return failure("transient");
  if (status === 409) return failure("conflict");
  return failure("permanent");
}

export function isAutomaticallyRetryable(failure: OutboxFailure | undefined) {
  return !failure || failure.category === "transient";
}

/** Maps a stored failure to localized, user-facing copy. */
export function describeOutboxFailure(
  failure: OutboxFailure | undefined,
  translate: UiTranslator,
): string {
  if (!failure) return translate("outboxFailureUnknown");
  if (failure.code === "unsupported_operation") return translate("outboxFailureUnsupported");
  if (failure.status === undefined) return translate("outboxFailureNetwork");
  if (failure.status === 401) return translate("outboxFailureSessionExpired");

  if (failure.status === 409 && !failure.code) return translate("outboxFailureConflict");

  return localizeError(
    new ApiError(failure.status, "", failure.code ? { code: failure.code } : {}),
    translate,
  );
}
