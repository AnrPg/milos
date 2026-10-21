"use client";

import { useTranslations } from "next-intl";

import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";

import { BackLink } from "./BuddyBits";
import { SupportRequestCard } from "./SupportRequestCard";
import { SupportStatus } from "./SupportStatus";
import { useSupportRequest } from "./use-buddies";

/**
 * One «Χρειάζομαι στήριξη», where its notifications lead: the buddy gets the
 * card with the quick replies, the sender the status (and the calm card).
 */
export function SupportRequestScreen({ requestId }: { requestId: string }) {
  const t = useTranslations("Buddy");
  const query = useSupportRequest(requestId);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <BackLink href="/me/buddy">{t("title")}</BackLink>
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("needSupport")}</h1>
      </div>
      {query.isPending ? (
        <LoadingLine />
      ) : query.isError ? (
        <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
      ) : query.data.role === "buddy" ? (
        query.data.status === "undone" ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("requestTakenBack")}</p>
        ) : (
          <SupportRequestCard request={query.data} />
        )
      ) : (
        <section className="rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <SupportStatus request={query.data} />
        </section>
      )}
    </div>
  );
}
