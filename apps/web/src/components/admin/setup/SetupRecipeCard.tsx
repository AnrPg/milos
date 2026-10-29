"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";

import { fetchSetupRecipes } from "@/api/setup";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

import { RECIPES_KEY } from "./SetupRecipes";

type Membership = { role?: string | null; roles?: string[] | null } | null | undefined;

const isOwner = (membership: Membership) => membership?.role === "owner" || Boolean(membership?.roles?.includes("owner"));

/**
 * Αρχική: «Τι είδους box έχεις;» for an owner whose box has applied no setup
 * recipe yet (ADR-255, mockup s10 A). Hidden once a recipe is applied.
 */
export function SetupRecipeCard({ membership }: { membership: Membership }) {
  const t = useTranslations("SetupRecipes");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const owner = isOwner(membership);
  const recipes = useQuery({
    queryKey: RECIPES_KEY,
    queryFn: () => fetchSetupRecipes(token!),
    enabled: Boolean(token && owner),
    staleTime: FRESHNESS.reference,
  });

  if (!owner || !recipes.data || !recipes.data.can_apply || recipes.data.applications.length > 0) return null;

  return (
    <section
      aria-labelledby="setup-recipe-card"
      data-testid="setup-recipe-card"
      className="flex flex-wrap items-center gap-4 rounded-[2.2rem] p-6"
      style={{ background: "var(--panel)", border: "1px solid var(--primary)" }}
    >
      <div className="min-w-0 flex-1">
        <p className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("welcome")}</p>
        <h2 id="setup-recipe-card" className="mt-1 text-lg font-semibold" style={{ color: "var(--text)" }}>
          {t("title")}
        </h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("intro")}</p>
      </div>
      <Link
        href={adminHref("/admin/setup", slug)}
        className="inline-flex min-h-10 items-center rounded-full px-5 text-sm font-semibold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {t("start")}
      </Link>
    </section>
  );
}
