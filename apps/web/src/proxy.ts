import { NextRequest, NextResponse } from "next/server";

import { retiredOrganizationSlugRedirect } from "@/lib/organization-slug-alias";

type MediaOriginEnv = Record<string, string | undefined>;

export function configuredMediaOrigins(env: MediaOriginEnv = process.env) {
  return (env.NEXT_PUBLIC_MEDIA_ORIGIN ?? env.MINIO_PUBLIC_ENDPOINT ?? "http://media.localhost:18080")
    .split(/[\s,]+/)
    .map((origin) => origin.trim())
    .filter(Boolean)
    .join(" ");
}

export async function proxy(request: NextRequest) {
  // ADR-122: a retired organization slug permanently redirects to the
  // canonical one, preserving the rest of the path and the query.
  const retiredSlugTarget = await retiredOrganizationSlugRedirect(request.method, request.nextUrl);
  if (retiredSlugTarget) {
    return applySecurityHeaders(NextResponse.redirect(retiredSlugTarget, 308));
  }

  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const mediaOrigins = configuredMediaOrigins();
  const development = process.env.NODE_ENV !== "production";

  const csp = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${development ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${mediaOrigins}`,
    "font-src 'self' data:",
    `connect-src 'self' ${mediaOrigins} ws: wss:`,
    "worker-src 'self' blob:",
    "manifest-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    ...(development ? [] : ["upgrade-insecure-requests"]),
  ].join("; ");

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);

  const organizationMatch = request.nextUrl.pathname.match(/^\/org\/[^/]+(\/.*)$/);
  const destination = organizationMatch?.[1];

  const response = destination
    ? NextResponse.rewrite(new URL(destination, request.url), {
        request: { headers: requestHeaders },
      })
    : NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set("Content-Security-Policy", csp);
  return applySecurityHeaders(response);
}

function applySecurityHeaders(response: NextResponse) {
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  return response;
}

export const config = {
  matcher: [
    {
      source: "/((?!api|socket|_next/static|_next/image|favicon.ico|sw-|manifest.webmanifest).*)",
    },
  ],
};
