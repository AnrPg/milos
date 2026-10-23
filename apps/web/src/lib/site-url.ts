import { headers } from "next/headers";

// The public origin search engines and link previews should use. Taken from
// NEXT_PUBLIC_SITE_URL when set, otherwise from the request (the ingress
// forwards the original host and scheme), so every deployment names itself.
export async function siteOrigin(env: Record<string, string | undefined> = process.env): Promise<URL> {
  const configured = env.NEXT_PUBLIC_SITE_URL?.trim();
  if (configured) return new URL(configured);

  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host") ?? "localhost:3000";
  const forwardedProto = requestHeaders.get("x-forwarded-proto")?.split(",")[0]?.trim();
  const protocol = forwardedProto || (host.startsWith("localhost") ? "http" : "https");
  return new URL(`${protocol}://${host.split(",")[0].trim()}`);
}
