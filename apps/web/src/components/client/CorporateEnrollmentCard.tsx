"use client";

import { useId, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";

import { enrollCorporateSeat } from "@/api/my-finance";
import { useSession } from "@/components/session-provider";
import { clientErrorMessage } from "@/components/client/errors";
import { CLIENT_ENTITLEMENT_QUERY_KEY } from "@/components/client/use-client-entitlement";
import { useUiTranslations } from "@/i18n/ui";

/**
 * "Company plan" (ADR-098): employees join their company's corporate plan
 * with its enrollment code, or without a code when the plan enrolls by the
 * account email's domain.
 */
export function CorporateEnrollmentCard({ onEnrolled }: { onEnrolled?: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const id = useId();
  const [code, setCode] = useState("");
  const [joined, setJoined] = useState(false);
  const enroll = useMutation({
    mutationFn: (withCode: string | null) => enrollCorporateSeat(tokens!.access_token, withCode),
    onSuccess: () => {
      setJoined(true);
      setCode("");
      void queryClient.invalidateQueries({ queryKey: CLIENT_ENTITLEMENT_QUERY_KEY });
      void queryClient.invalidateQueries({ queryKey: ["my", "finance"] });
      onEnrolled?.();
    },
  });
  const busy = enroll.isPending || !tokens?.access_token;

  return (
    <section
      aria-labelledby={`${id}-title`}
      className="flex flex-col gap-3 rounded-2xl p-5"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <h2 id={`${id}-title`} className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
        {i18n("clCorporateTitle")}
      </h2>
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {i18n("clCorporateIntro")}
      </p>

      {joined ? (
        <p role="status" className="text-sm font-semibold" style={{ color: "var(--success)" }}>
          {i18n("clCorporateJoined")}
        </p>
      ) : (
        <>
          <form
            className="flex flex-col gap-2 sm:flex-row sm:items-end"
            onSubmit={(event) => {
              event.preventDefault();
              if (code.trim()) enroll.mutate(code);
            }}
          >
            <div className="flex-1">
              <label htmlFor={`${id}-code`} className="mb-1 block text-xs font-semibold" style={{ color: "var(--muted)" }}>
                {i18n("clCorporateCode")}
              </label>
              <input
                id={`${id}-code`}
                value={code}
                autoComplete="off"
                autoCapitalize="characters"
                spellCheck={false}
                maxLength={64}
                onChange={(event) => setCode(event.target.value)}
                className="w-full rounded-lg px-3 py-2 font-mono text-sm outline-none"
                style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text)" }}
              />
            </div>
            <button
              type="submit"
              disabled={busy || !code.trim()}
              className="rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {enroll.isPending && enroll.variables ? i18n("clCorporateJoining") : i18n("clCorporateJoin")}
            </button>
          </form>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs" style={{ color: "var(--dim)" }}>
              {i18n("clCorporateByEmailHelp")}
            </span>
            <button
              type="button"
              disabled={busy}
              onClick={() => enroll.mutate(null)}
              className="rounded-lg px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
            >
              {enroll.isPending && !enroll.variables ? i18n("clCorporateJoining") : i18n("clCorporateByEmail")}
            </button>
          </div>
          {enroll.isError ? (
            <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
              {clientErrorMessage(enroll.error, i18n)}
            </p>
          ) : null}
        </>
      )}
    </section>
  );
}
