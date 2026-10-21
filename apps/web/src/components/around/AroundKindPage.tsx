"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { AroundItem, AroundKind } from "@/api/around";
import { ErrorLine } from "@/components/community/Sheet";
import { HubCard, HubPage } from "@/components/member-app/HubParts";

import { useAroundError } from "./AreaPicker";
import { AroundChipRow, useKm } from "./AroundFilters";
import { AroundRow, itemPinId } from "./AroundSections";
import { needsOrigin, useAround, useAroundKind } from "./use-around";

/** «Δες όλα»: one kind near you, with the same filters, paged by cursor. */
export function AroundKindPage({ kind }: { kind: AroundKind }) {
  const t = useTranslations("Around");
  const km = useKm();
  const aroundError = useAroundError();
  const { ready, queryFilter, origin } = useAround();
  const list = useAroundKind(kind, { filter: queryFilter, origin, enabled: ready });
  const pages = list.data?.pages ?? [];
  const items = pages.flatMap((page) => page.items as AroundItem[]);
  const total = pages[0]?.total ?? 0;

  return (
    <HubPage title={t(["section", kind].join("_"))}>
      <Link href="/around" className="-mt-2 flex min-h-10 items-center gap-1 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
        <span aria-hidden="true">‹</span> {t("backToAround")}
      </Link>
      <AroundChipRow resultCount={total} />
      {list.isPending || !ready ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : list.isError && items.length === 0 ? (
        <HubCard>
          {needsOrigin(list.error) ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>
              {t("needArea")}{" "}
              <Link href="/around" className="font-semibold underline" style={{ color: "var(--text)" }}>{t("chooseArea")}</Link>
            </p>
          ) : (
            <>
              <ErrorLine message={aroundError(list.error)} />
              <button
                type="button"
                onClick={() => void list.refetch()}
                className="mt-3 min-h-11 rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
              >
                {t("retry")}
              </button>
            </>
          )}
        </HubCard>
      ) : (
        <>
          <p className="text-sm" style={{ color: "var(--dim)" }} aria-live="polite">
            {t("kindCount", { count: total, distance: km(queryFilter.radius_km) })}
          </p>
          {items.length === 0 ? (
            <HubCard>
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>
                {t(["empty", kind].join("_"), { distance: km(queryFilter.radius_km) })}
              </p>
            </HubCard>
          ) : (
            <ul className="flex flex-col gap-2">
              {items.map((item) => (
                <AroundRow key={itemPinId(kind, item)} kind={kind} item={item} />
              ))}
            </ul>
          )}
          {list.hasNextPage ? (
            <button
              type="button"
              onClick={() => void list.fetchNextPage()}
              disabled={list.isFetchingNextPage}
              className="min-h-11 rounded-2xl text-sm font-semibold disabled:opacity-50"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {list.isFetchingNextPage ? t("loadingMore") : t("loadMore")}
            </button>
          ) : null}
          {list.isFetchNextPageError ? <ErrorLine message={aroundError(list.error)} /> : null}
        </>
      )}
    </HubPage>
  );
}
