"use client";

import { usePathname, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";

import { fetchOrganizationMemberships } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

export function OrganizationSelector() {
  const i18n = useUiTranslations();
  const pathname = usePathname();
  const router = useRouter();
  const { tokens } = useSession();

  const memberships = useQuery({
    queryKey: ["organization-memberships"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchOrganizationMemberships(tokens!.access_token),
    staleTime: 60_000,
  });

  const selectedSlug = pathname.match(/^\/org\/([^/]+)/)?.[1] ?? "";
  if (!memberships.data?.length) return null;

  return (
    <select
      aria-label={i18n("organization")}
      className="max-w-40 rounded-md px-2 py-1 text-xs outline-none"
      onChange={(event) => {
        const slug = event.target.value;
        const membership = memberships.data.find((entry) => entry.organization.slug === slug);
        if (!membership) return;

        router.push(
          ["owner", "admin", "coach"].includes(membership.role)
            ? `/org/${slug}/admin`
            : `/org/${slug}`,
        );
      }}
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      value={selectedSlug}
    >
      <option value="">{i18n("organization")}</option>
      {memberships.data.map((entry) => (
        <option key={entry.id} value={entry.organization.slug}>
          {entry.organization.name}
        </option>
      ))}
    </select>
  );
}
