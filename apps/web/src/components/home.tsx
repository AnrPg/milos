"use client";

import { usePathname } from "next/navigation";

import { useSession } from "@/components/session-provider";
import { LandingPage } from "@/components/landing-page";
import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";

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
export function Home() {
  const pathname = usePathname();
  const { currentUser } = useSession();
  const inOrganizationContext = pathname.startsWith("/org/");

  if (currentUser?.vendor && !inOrganizationContext) return <PlatformOrganizationsPage />;

  return <LandingPage />;
}
