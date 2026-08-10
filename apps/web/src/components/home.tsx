"use client";

import { useSession } from "@/components/session-provider";
import { LandingPage } from "@/components/landing-page";
import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";

// Vendors (SaaS operators) have no tenant homepage to speak of - the
// platform console *is* their home. "/platform/organizations" stays live
// as an alias (bookmarks, the TopNav dropdown link) pointing at the same
// component.
export function Home() {
  const { currentUser } = useSession();

  if (currentUser?.vendor) return <PlatformOrganizationsPage />;

  return <LandingPage />;
}
