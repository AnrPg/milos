"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";

import {
  fetchDocumentSettings,
  fetchDocumentTemplates,
  fetchHealthCertificates,
  fetchMyDocuments,
  fetchMySignatures,
  fetchOutstanding,
} from "@/api/documents";
import { useSession } from "@/components/session-provider";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { FRESHNESS } from "@/lib/query-policy";
import { can } from "@/lib/role-navigation";

// Data access of the documents screens (ADR-215: no token in query keys,
// each query enabled only where it is shown).

export const documentKeys = {
  all: (slug: string | null) => ["documents", slug] as const,
  templates: (slug: string | null) => ["documents", slug, "templates"] as const,
  outstanding: (slug: string | null) => ["documents", slug, "outstanding"] as const,
  settings: (slug: string | null) => ["documents", slug, "settings"] as const,
  health: (slug: string | null) => ["documents", slug, "health"] as const,
  member: (slug: string | null, userId: string) => ["documents", slug, "member", userId] as const,
  mine: (slug: string | null) => ["documents", slug, "mine"] as const,
  mySignatures: (slug: string | null) => ["documents", slug, "mine", "signatures"] as const,
};

export function useToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/**
 * Who sees what (ADR-252 §7): documents, requests and signatures need
 * `manage_settings`, `manage_memberships` or `request_signatures` (front
 * desk); the evidence PDF the first two; writing documents and the booking
 * gate need `manage_settings`; certificate dates and files need
 * `manage_health_certificates` or `view_health_certificates` (front desk),
 * uploads the former; `view_health` (coaches) sees status only.
 */
export function useDocumentsAccess() {
  const { membership, isLoading } = useSelectedMembershipRole();
  const manage = can(membership, "manage_settings");
  // The evidence PDF stays with settings and memberships staff.
  const evidence = manage || can(membership, "manage_memberships");
  // Front desk asks clients to sign and sees who has not (product owner, 2026-10-29).
  const documents = evidence || can(membership, "request_signatures");
  // ...and sees certificate dates and files; uploading and deleting need manage_health_certificates.
  const healthWrite = can(membership, "manage_health_certificates");
  const healthFull = healthWrite || can(membership, "view_health_certificates");
  const health = healthFull || can(membership, "view_health");
  return { isLoading, manage, documents, evidence, health, healthFull, healthWrite, any: documents || health };
}

export function useStaffDocuments() {
  const token = useToken();
  const slug = useOrganizationSlug();
  const access = useDocumentsAccess();
  const templates = useQuery({
    queryKey: documentKeys.templates(slug),
    enabled: Boolean(token && access.documents),
    staleTime: FRESHNESS.live,
    queryFn: () => fetchDocumentTemplates(token!),
  });
  const outstanding = useQuery({
    queryKey: documentKeys.outstanding(slug),
    enabled: Boolean(token && access.documents),
    staleTime: FRESHNESS.live,
    queryFn: () => fetchOutstanding(token!),
  });
  const settings = useQuery({
    queryKey: documentKeys.settings(slug),
    enabled: Boolean(token && access.manage),
    staleTime: FRESHNESS.reference,
    queryFn: () => fetchDocumentSettings(token!),
  });
  const health = useQuery({
    queryKey: documentKeys.health(slug),
    enabled: Boolean(token && access.health),
    staleTime: FRESHNESS.live,
    queryFn: () => fetchHealthCertificates(token!),
  });
  return { token, slug, access, templates, outstanding, settings, health };
}

export function useInvalidateDocuments() {
  const queryClient = useQueryClient();
  const slug = useOrganizationSlug();
  return useCallback(() => queryClient.invalidateQueries({ queryKey: documentKeys.all(slug) }), [queryClient, slug]);
}

/** Box › Έγγραφα: the client's documents in the selected box. */
export function useMyDocuments(enabled = true) {
  const token = useToken();
  const slug = useOrganizationSlug();
  return useQuery({
    queryKey: documentKeys.mine(slug),
    enabled: Boolean(token && slug && enabled),
    staleTime: FRESHNESS.live,
    queryFn: () => fetchMyDocuments(token!),
  });
}

export function useMySignatures() {
  const token = useToken();
  const slug = useOrganizationSlug();
  return useQuery({
    queryKey: documentKeys.mySignatures(slug),
    enabled: Boolean(token && slug),
    staleTime: FRESHNESS.live,
    queryFn: () => fetchMySignatures(token!),
  });
}

/** Opens a short-lived file link (a certificate PDF, a health certificate) in a new tab. */
export async function openLink(load: () => Promise<{ url: string }>) {
  const opened = typeof window !== "undefined" ? window.open("", "_blank") : null;
  try {
    const { url } = await load();
    if (opened) opened.location.href = url;
    else if (typeof window !== "undefined") window.location.assign(url);
  } catch (error) {
    opened?.close();
    throw error;
  }
}
