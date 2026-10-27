"use client";

import { useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  enrollCorporateSeat,
  fetchCorporateEnrollmentOffer,
  requestCorporateVerificationEmail,
} from "@/api/my-finance";
import { useSession } from "@/components/session-provider";
import { clientErrorMessage } from "@/components/client/errors";
import { companyCodeFromSearch, needsEmailConfirmation } from "@/components/client/corporate-enrollment";
import { CLIENT_ENTITLEMENT_QUERY_KEY } from "@/components/client/use-client-entitlement";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Company plan enrollment (ADR-098). Company-paid plans are rare, so the card
 * stays hidden unless it applies: the member opened the enrollment link their
 * employer shared (`?company_code=`), or their account email matches an
 * email-domain plan they have not joined yet. ADR-205: an email-domain match
 * joins only once the email is confirmed; until then the card says so and
 * offers to send the confirmation link again.
 */
export function CorporateEnrollmentCard({ onEnrolled }: { onEnrolled?: () => void }) {
  const i18n = useUiTranslations();
  const t = useTranslations("VerifiedGates");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const id = useId();
  // The billing page renders behind the signed-in session, on the client.
  const [linkCode] = useState(() =>
    typeof window === "undefined" ? null : companyCodeFromSearch(window.location.search),
  );
  const [joined, setJoined] = useState(false);

  const offer = useQuery({
    queryKey: ["my", "corporate-enrollment-offer"],
    queryFn: () => fetchCorporateEnrollmentOffer(token!),
    enabled: Boolean(token),
    staleTime: 5 * 60_000,
  });

  const enroll = useMutation({
    mutationFn: (code: string | null) => enrollCorporateSeat(token!, code),
    onSuccess: () => {
      setJoined(true);
      if (linkCode) window.history.replaceState(null, "", window.location.pathname);
      void queryClient.invalidateQueries({ queryKey: CLIENT_ENTITLEMENT_QUERY_KEY });
      void queryClient.invalidateQueries({ queryKey: ["my", "finance"] });
      void queryClient.invalidateQueries({ queryKey: ["my", "corporate-enrollment-offer"] });
      onEnrolled?.();
    },
  });

  const resend = useMutation({ mutationFn: () => requestCorporateVerificationEmail(token!) });

  const companyName = offer.data?.company_name ?? null;
  if (!joined && !linkCode && !companyName) return null;
  const confirmFirst = !joined && needsEmailConfirmation(linkCode, offer.data ?? null, enroll.error);

  return (
    <section
      aria-labelledby={`${id}-title`}
      className="flex flex-col gap-3 rounded-2xl p-5"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <h2 id={`${id}-title`} className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
        {i18n("clCorporateTitle")}
      </h2>

      {joined ? (
        <p role="status" className="text-sm font-semibold" style={{ color: "var(--success)" }}>
          {i18n("clCorporateJoined")}
        </p>
      ) : confirmFirst ? (
        <>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {t("corporate.confirmToJoin", { company: companyName ?? "" })}
          </p>
          <div>
            <button
              type="button"
              disabled={resend.isPending || resend.isSuccess || !token}
              onClick={() => resend.mutate()}
              className="rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {resend.isPending ? t("corporate.sending") : t("corporate.resend")}
            </button>
          </div>
          {resend.isSuccess ? (
            <p role="status" className="text-sm" style={{ color: "var(--success)" }}>
              {t("corporate.sent")}
            </p>
          ) : null}
          {resend.isError ? <ErrorNotice>{clientErrorMessage(resend.error, i18n)}</ErrorNotice> : null}
        </>
      ) : (
        <>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {linkCode
              ? i18n("clCorporateInviteIntro", { code: linkCode })
              : i18n("clCorporateOfferIntro", { company: companyName ?? "" })}
          </p>
          <div>
            <button
              type="button"
              disabled={enroll.isPending || !token}
              onClick={() => enroll.mutate(linkCode)}
              className="rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {enroll.isPending ? i18n("clCorporateJoining") : i18n("clCorporateJoinCompany")}
            </button>
          </div>
          {enroll.isError ? (
            <ErrorNotice>{clientErrorMessage(enroll.error, i18n)}</ErrorNotice>
          ) : null}
        </>
      )}
    </section>
  );
}
