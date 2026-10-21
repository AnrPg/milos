import { clientErrorMessage } from "@/components/client/errors";

import { partnerErrorCode } from "./partners-model";

/** Partners' own wording for its errors, else the shared client wording. */
export function partnerErrorMessage(
  error: unknown,
  t: (key: string) => string,
  tUi: Parameters<typeof clientErrorMessage>[1],
): string | null {
  if (!error) return null;
  const code = partnerErrorCode(error);
  return code ? t(["error", code].join("_")) : clientErrorMessage(error, tUi);
}
