"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { likelyScreens, staffNavItems } from "@/lib/role-navigation";

/**
 * ADR-178: once the app is idle after sign-in, preload the screens the role
 * most likely opens next (page payload and code), so a tap renders from the
 * client cache instead of waiting on the network. Renders nothing.
 */
export function ScreenPreloader() {
  const router = useRouter();
  const { status } = useSession();
  const { role, membership, selectedOrganizationSlug, isLoading } = useSelectedMembershipRole();
  const ready = status === "authenticated" && !isLoading && Boolean(membership);
  const hrefs = ready
    ? likelyScreens(role, role === "admin" ? staffNavItems(membership) : []).map((item) =>
        item.scoped ? adminHref(item.href, selectedOrganizationSlug) : item.href,
      )
    : [];
  const key = hrefs.join(" ");

  useEffect(() => {
    if (!key) return;
    const preload = () => key.split(" ").forEach((href) => router.prefetch(href));
    // Wait for the first screen to settle; fall back to a timer where
    // requestIdleCallback is missing (Safari).
    if (typeof window.requestIdleCallback === "function") {
      const id = window.requestIdleCallback(preload, { timeout: 3_000 });
      return () => window.cancelIdleCallback(id);
    }
    const id = window.setTimeout(preload, 1_500);
    return () => window.clearTimeout(id);
  }, [key, router]);

  return null;
}
