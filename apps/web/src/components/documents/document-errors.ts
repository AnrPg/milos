import { ApiError } from "@/api/client";
import { localizeError } from "@/i18n/presentation";
import type { UiTranslator } from "@/i18n/presentation";

type Translate = (key: string, values?: Record<string, string | number>) => string;

const CODES: Record<string, string> = {
  document_version_outdated: "errorVersionOutdated",
  document_archived: "errorArchived",
  document_not_published: "errorNotPublished",
  signature_evidence_unavailable: "errorEvidenceUnavailable",
  health_certificate_file_invalid: "errorFileInvalid",
  health_certificate_file_missing: "errorFileMissing",
};

const FIELDS: Record<string, Record<string, string>> = {
  issued_on: { in_future: "errorIssuedInFuture", required: "errorIssuedRequired", invalid: "errorIssuedRequired" },
  expires_on: { already_expired: "errorAlreadyExpired", too_late: "errorTooLate", before_issue: "errorBeforeIssue" },
  content_type: { unsupported: "errorFileInvalid" },
  typed_name: { too_short: "errorTypedName", too_long: "errorTypedName", signature_required: "errorSignatureRequired" },
  drawn_signature: { invalid: "errorDrawn" },
  agreed: { required: "errorSignatureRequired" },
  title: { required: "errorTitleRequired" },
  body: { required: "errorBodyRequired" },
};

/** The field an error belongs to, so the form can show it under that field (ADR-214). */
export type DocumentFieldErrors = Partial<Record<string, string>>;

/**
 * Plain-words messages for the documents endpoints (ADR-252), with the
 * field each one belongs to; anything else falls back to the shared
 * `localizeError`.
 */
export function documentError(error: unknown, t: Translate, i18n: UiTranslator): { message: string; fields: DocumentFieldErrors } {
  if (error instanceof ApiError) {
    const code = error.payload.code;
    if (code && CODES[code]) return { message: t(CODES[code]), fields: {} };
    const errors = error.payload.errors;
    if (error.status === 422 && errors && typeof errors === "object") {
      const fields: DocumentFieldErrors = {};
      for (const [field, value] of Object.entries(errors)) {
        const reason = Array.isArray(value) ? String(value[0]) : String(value);
        const key = FIELDS[field]?.[reason];
        if (key) fields[field] = t(key);
      }
      const first = Object.values(fields)[0];
      if (first) return { message: first, fields };
    }
  }
  return { message: localizeError(error, i18n), fields: {} };
}
