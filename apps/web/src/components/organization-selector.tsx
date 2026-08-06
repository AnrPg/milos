"use client";

import { useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { usePathname, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { fetchOrganizationMemberships } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

type OrganizationSelectorProps = {
  variant?: "nav" | "menu";
  onSelect?: () => void;
};

function organizationDisplayName(entry: {
  organization: { name: string };
  settings?: { brand_name?: string | null } | null;
}) {
  return entry.settings?.brand_name?.trim() || entry.organization.name;
}

export function OrganizationSelector({ variant = "nav", onSelect }: OrganizationSelectorProps) {
  const i18n = useUiTranslations();
  const pathname = usePathname();
  const router = useRouter();
  const queryClient = useQueryClient();
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
  const selectedMembership = selectedSlug ? membershipsBySlug.get(selectedSlug) : null;
  const selectedLogoUrl = selectedMembership?.settings?.brand_logo_url?.trim() || "";

  useEffect(() => {
    if (!selectedSlug || selectedSlug === storedSlug) return;

    try {
      window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, selectedSlug);
    } catch {}
  }, [selectedSlug, storedSlug]);

  if (membershipList.length <= 1) return null;

  const wrapperClassName =
    variant === "menu"
      ? "flex items-center gap-2 border-t px-4 py-2.5"
      : "flex max-w-56 shrink-0 items-center gap-2";
  const selectClassName =
    variant === "menu"
      ? "min-w-0 flex-1 rounded-md px-2 py-1.5 text-xs outline-none"
      : "min-w-0 max-w-40 rounded-md px-2 py-1 text-xs outline-none";

  return (
    <div className={wrapperClassName} style={variant === "menu" ? { borderColor: "var(--border)" } : undefined}>
      {selectedLogoUrl ? (
        <Image
          alt=""
          aria-hidden="true"
          className="h-7 w-7 rounded-md object-contain"
          height={28}
          src={selectedLogoUrl}
          unoptimized
          width={28}
        />
      ) : null}
      <select
        aria-label={i18n("organization")}
        className={selectClassName}
        onChange={(event) => {
          const slug = event.target.value;
          const membership = membershipsBySlug.get(slug);
          if (!membership) return;

          try {
            window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, slug);
          } catch {}
          setStoredSlug(slug);
          queryClient.clear();

          router.push(
            ["owner", "admin", "coach"].includes(membership.role)
              ? `/org/${slug}/admin`
              : `/org/${slug}`,
          );
          onSelect?.();
        }}
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        value={selectedSlug}
      >
        <option value="">{i18n("organization")}</option>
        {membershipList.map((entry) => (
          <option key={entry.id} value={entry.organization.slug}>
            {organizationDisplayName(entry)}
          </option>
        ))}
      </select>
    </div>
  );
}
