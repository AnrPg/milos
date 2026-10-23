import type { Metadata } from "next";

import { AuthGuard } from "@/components/auth-guard";
import { ProductOverview } from "@/components/about/ProductOverview";
import { Home } from "@/components/home";
import { loadSiteFacts } from "@/lib/seo/site-facts";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { alternates: { canonical: "/" } };

export default async function HomeRoute() {
  const { faq } = await loadSiteFacts();
  return (
    <>
      {/* The session lives in the browser, so the server cannot tell a guest
          from a member; crawlers that skip JavaScript read the overview here
          instead of the "restoring session" placeholder. */}
      <noscript>
        <ProductOverview faq={faq} />
      </noscript>
      <AuthGuard roleRedirects={{ admin: "/admin" }}>
        <Home />
      </AuthGuard>
    </>
  );
}
