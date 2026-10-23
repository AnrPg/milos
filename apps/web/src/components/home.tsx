"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";

import { useSession } from "@/components/session-provider";
import { HomeHub } from "@/components/member-app/HomeHub";
import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";
import { needsFirstRun } from "@/lib/first-run";

// Vendors (SaaS operators) have no tenant homepage to speak of by default -
// the platform console *is* their home. "/platform/organizations" stays
// live as an alias (bookmarks, the TopNav dropdown link) pointing at the
// same component.
//
// A vendor who also holds a real membership somewhere can still choose to
// view that org as that role: navigating under /org/:slug (via the "Your
// memberships" links on the platform page, or the TopNav dropdown) always
// renders the ordinary tenant workspace, vendor status notwithstanding -
// only the bare "/" defaults to the platform console.
//
// Everyone else reaching "/" is a member or athlete (admins are redirected to
// /admin by the route), so "/" is the Αρχική hub (ADR-137).
export function Home() {
  const pathname = usePathname();
  const router = useRouter();
  const { currentUser } = useSession();
  const inOrganizationContext = pathname.startsWith("/org/");
  // ADR-183: a new account's first stop is the first-run, once.
  const firstRun = needsFirstRun(currentUser);

  useEffect(() => {
    if (firstRun) router.replace("/welcome");
  }, [firstRun, router]);

  if (firstRun) return null;
  if (currentUser?.vendor && !inOrganizationContext) return <PlatformOrganizationsPage />;

  return <HomeHub />;
}
