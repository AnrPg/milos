"use client";

import { useParams } from "next/navigation";

import { useOrganizationMemberships } from "@/lib/organization-slug";

export default function OrganizationContextPage() {
  const params = useParams<{ organization_slug: string }>();
  const memberships = useOrganizationMemberships();

  const membership = memberships.data?.find(
    (entry) => entry.organization.slug === params.organization_slug,
  );

  if (!membership) return null;

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6">
      <h1 className="text-2xl font-bold" style={{ color: "var(--text)" }}>
        {membership.organization.name}
      </h1>
      <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
        {membership.role}
      </p>
    </main>
  );
}
