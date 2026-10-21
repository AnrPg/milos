import { appleAppSiteAssociation } from "@/lib/platform/app-links";

// ADR-171: lets iOS open the share links in the Palee app (universal links).
// Read at request time so APPLE_TEAM_ID can change without a rebuild; 404
// until it is set.
export const dynamic = "force-dynamic";

export function GET() {
  const document = appleAppSiteAssociation();
  if (!document) return new Response("Not found", { status: 404 });
  return Response.json(document, { headers: { "Cache-Control": "public, max-age=3600" } });
}
