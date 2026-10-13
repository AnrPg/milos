"use client";

import { useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { enrollCorporateSeat, fetchCorporateEnrollmentOffer } from "@/api/my-finance";
import { useSession } from "@/components/session-provider";
import { clientErrorMessage } from "@/components/client/errors";
import { companyCodeFromSearch } from "@/components/client/corporate-enrollment";
import { CLIENT_ENTITLEMENT_QUERY_KEY } from "@/components/client/use-client-entitlement";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Company plan enrollment (ADR-098). Company-paid plans are rare, so the card
 * stays hidden unless it applies: the member opened the enrollment link their
 * employer shared (`?company_code=`), or their account email matches an
 * email-domain plan they have not joined yet.
 */
export function CorporateEnrollmentCard({ onEnrolled }: { onEnrolled?: () => void }) {
  const i18n = useUiTranslations();
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

  const companyName = offer.data?.company_name ?? null;
  if (!joined && !linkCode && !companyName) return null;

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
            <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
              {clientErrorMessage(enroll.error, i18n)}
            </p>
          ) : null}
        </>
      )}
    </section>
  );
}
