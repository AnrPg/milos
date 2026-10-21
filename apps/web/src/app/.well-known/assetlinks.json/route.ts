import { assetLinks } from "@/lib/platform/app-links";

// ADR-171: lets Android open the share links in the Palee app (App Links).
// Read at request time so the signing fingerprints can change without a
// rebuild; 404 until ANDROID_SHA256_CERT_FINGERPRINTS is set.
export const dynamic = "force-dynamic";

export function GET() {
  const statements = assetLinks();
  if (!statements) return new Response("Not found", { status: 404 });
  return Response.json(statements, { headers: { "Cache-Control": "public, max-age=3600" } });
}
