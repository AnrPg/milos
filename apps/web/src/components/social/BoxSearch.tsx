"use client";

import Link from "next/link";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { boxSearchKey, searchBoxes, type BoxSearchResult } from "@/api/social";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { isPeopleSearch } from "./social-model";

/**
 * Boxes and independent coaches by name (ADR-216): only businesses that are
 * live and published their page answer, from two characters on, accents and
 * case ignored. Γύρω μου finds them by place; this finds them by name.
 */
export function useBoxSearch(term: string) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const q = term.trim();
  return useQuery({
    queryKey: boxSearchKey(q),
    enabled: Boolean(token) && isPeopleSearch(q),
    queryFn: () => searchBoxes(token!, q),
    placeholderData: keepPreviousData,
  });
}

/** One result: logo, name, kind and area, then Follow; the row opens the public page. */
export function BoxResultRow({ box }: { box: BoxSearchResult }) {
  const tProviders = useTranslations("Providers");
  const place = box.neighbourhood || box.city;
  return (
    <li className="flex items-center gap-3 rounded-3xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <Link href={`/b/${encodeURIComponent(box.slug)}`} className="flex min-w-0 flex-1 items-center gap-3">
        <PersonAvatar name={box.name} url={box.logo_url} />
        <span className="min-w-0">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{box.name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {[tProviders(`kind.${box.provider_kind}`), place].filter(Boolean).join(" · ")}
          </span>
        </span>
      </Link>
      <div className="shrink-0">
        <FollowButton targetType="organization" targetId={box.organization_id} initialStatus={box.my_status} />
      </div>
    </li>
  );
}

/** The results list, or why it is empty. `null` while the term is too short. */
export function BoxResults({ term }: { term: string }) {
  const t = useTranslations("Social");
  const found = useBoxSearch(term);
  if (!isPeopleSearch(term)) return null;
  const boxes = found.data?.boxes ?? [];
  if (found.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (found.isError) return <ErrorNotice>{t("boxSearchFailed")}</ErrorNotice>;
  if (boxes.length === 0)
    return (
      <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
        {t("boxNoMatch")}
      </p>
    );
  return (
    <ul className="flex flex-col gap-2" aria-live="polite">
      {boxes.map((box) => (
        <BoxResultRow key={box.organization_id} box={box} />
      ))}
    </ul>
  );
}
