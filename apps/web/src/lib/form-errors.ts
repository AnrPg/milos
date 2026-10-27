import { ApiError } from "@/api/client";
import {
  explainFieldMessage,
  fieldMessagesOf,
  localizeError,
  type UiTranslator,
} from "@/i18n/presentation";

export { explainFieldMessage, fieldMessagesOf };

/**
 * ADR-205: how a form shows what went wrong. A wrong field turns red and says,
 * right under it and in plain words, why it is wrong and how to fix it; what
 * belongs to no field shows as one notice inside the same form (the dialog's
 * `error` slot), never on the page behind it.
 *
 * - `fields`: one message per field the form shows, keyed as the API names it.
 * - `message`: the form-level notice, or null.
 */
export type FormErrors<Field extends string = string> = {
  fields: Partial<Record<Field, string>>;
  message: string | null;
};

export const NO_FORM_ERRORS: FormErrors<never> = { fields: {}, message: null };

export function hasFormErrors(errors: FormErrors<string>): boolean {
  return Boolean(errors.message) || Object.values(errors.fields).some(Boolean);
}

/** A field's own explanation, when the generic wording for its rule is not enough. */
export type FieldMessageOverride = (rawMessage: string) => string | null | undefined;

/**
 * Turns a failed request into form errors. Messages for the fields the form
 * shows (`fields`, as the API names them) land on those fields; any other
 * field's reason joins the form-level notice, so nothing is lost and the
 * notice never promises a highlight that is not there.
 */
export function formErrorsFrom<Field extends string>(
  error: unknown,
  translate: UiTranslator,
  fields: readonly Field[],
  options: { fallback?: string; overrides?: Partial<Record<Field, FieldMessageOverride>> } = {},
): FormErrors<Field> {
  const raw = error instanceof ApiError && error.status === 422 ? fieldMessagesOf(error.payload.errors) : {};
  const shown: Partial<Record<Field, string>> = {};
  const elsewhere = new Set<string>();

  for (const [field, messages] of Object.entries(raw)) {
    if (!(fields as readonly string[]).includes(field)) {
      // A field the form does not show: the reason alone, in plain words.
      elsewhere.add(explainFieldMessage(messages[0], translate));
      continue;
    }
    const override = options.overrides?.[field as Field];
    shown[field as Field] = override?.(messages[0]) ?? explainFieldMessage(messages[0], translate);
  }

  const shownCount = Object.keys(shown).length;
  if (shownCount === 0 && elsewhere.size === 0) {
    return {
      fields: {},
      message: error instanceof ApiError ? localizeError(error, translate) : (options.fallback ?? translate("apiErrorRequestFailed")),
    };
  }

  const parts = [shownCount > 0 ? translate("formErrFixHighlighted") : null, ...elsewhere].filter(Boolean);
  return { fields: shown, message: parts.join(" ") };
}

/**
 * Props for an input that may be wrong: red border, `aria-invalid`, and the id
 * of the explanation under it. Spread them onto the control and render
 * `<FieldError>` with the same id.
 */
export function invalidFieldProps(message: string | null | undefined, errorId: string) {
  return message
    ? ({ "aria-invalid": true, "aria-describedby": errorId } as const)
    : ({} as Record<string, never>);
}

/** The border of a field: red when wrong, the theme's control border otherwise. */
export function fieldBorder(message: string | null | undefined, normal = "1px solid var(--border)"): string {
  return message ? "1px solid var(--danger)" : normal;
}

/**
 * The server's field errors that still apply: a field's message goes away as
 * soon as its value differs from the one that was sent, so a corrected field
 * stops being red without waiting for the next save.
 */
export function stillApplies<Field extends string>(
  errors: FormErrors<Field> | null | undefined,
  sent: Partial<Record<Field, unknown>> | null | undefined,
  current: Partial<Record<Field, unknown>>,
): Partial<Record<Field, string>> {
  if (!errors) return {};
  const result: Partial<Record<Field, string>> = {};
  for (const [field, message] of Object.entries(errors.fields) as Array<[Field, string | undefined]>) {
    if (!message) continue;
    if (!sent || JSON.stringify(sent[field] ?? null) === JSON.stringify(current[field] ?? null)) result[field] = message;
  }
  return result;
}
