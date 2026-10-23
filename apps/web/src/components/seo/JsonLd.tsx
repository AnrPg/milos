import { headers } from "next/headers";

import { serializeJsonLd } from "@/lib/seo/site-info";

// Structured data for search and AI answer engines (schema.org JSON-LD).
export async function JsonLd({ data }: { data: unknown }) {
  const nonce = (await headers()).get("x-nonce") ?? undefined;
  return (
    <script
      type="application/ld+json"
      nonce={nonce}
      dangerouslySetInnerHTML={{ __html: serializeJsonLd(data) }}
    />
  );
}
