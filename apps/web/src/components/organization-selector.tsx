"use client";

import { useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { fetchOrganizationMemberships } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

export function OrganizationSelector() {
  const i18n = useUiTranslations();
  const pathname = usePathname();
  const router = useRouter();
  const { tokens } = useSession();
  const [storedSlug, setStoredSlug] = useState(() => {
    if (typeof window === "undefined") return "";
    try {
      return window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY) ?? "";
    } catch {
      return "";
    }
  });

  const memberships = useQuery({
    queryKey: ["organization-memberships"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchOrganizationMemberships(tokens!.access_token),
    staleTime: 60_000,
  });

  const pathSlug = pathname.match(/^\/org\/([^/]+)/)?.[1] ?? "";
  const membershipList = useMemo(
    () => (Array.isArray(memberships.data) ? memberships.data : []),
    [memberships.data],
  );
  const membershipsBySlug = useMemo(
    () => new Map(membershipList.map((entry) => [entry.organization.slug, entry])),
    [membershipList],
  );
  const fallbackSlug = membershipList[0]?.organization.slug ?? "";
  const selectedSlug =
    pathSlug && membershipsBySlug.has(pathSlug)
      ? pathSlug
      : storedSlug && membershipsBySlug.has(storedSlug)
        ? storedSlug
        : fallbackSlug;

  useEffect(() => {
    if (!selectedSlug || selectedSlug === storedSlug) return;

    try {
      window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, selectedSlug);
    } catch {}
  }, [selectedSlug, storedSlug]);

  if (!membershipList.length) return null;

  return (
    <select
      aria-label={i18n("organization")}
      className="max-w-40 rounded-md px-2 py-1 text-xs outline-none"
      onChange={(event) => {
        const slug = event.target.value;
        const membership = membershipsBySlug.get(slug);
        if (!membership) return;

        try {
          window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, slug);
        } catch {}
        setStoredSlug(slug);

        router.push(
          ["owner", "admin", "coach"].includes(membership.role)
            ? "/admin"
            : `/org/${slug}`,
        );
      }}
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      value={selectedSlug}
    >
      <option value="">{i18n("organization")}</option>
      {membershipList.map((entry) => (
        <option key={entry.id} value={entry.organization.slug}>
          {entry.organization.name}
        </option>
      ))}
    </select>
  );
}
