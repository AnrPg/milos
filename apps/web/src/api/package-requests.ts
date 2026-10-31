// ADR-291: «Το θέλω». When a box takes no online payments, a person asks for
// a package in the app and pays at the front desk; it waits 14 days as
// «Περιμένει πληρωμή» and shows in the desk's «Εκκρεμότητες», where
// «Είσπραξη» records the money and assigns the package in one step.
import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type Json<Op extends keyof operations> = operations[Op] extends {
  responses: { 200: { content: { "application/json": infer T } } };
}
  ? T
  : never;

type Body<Op extends keyof operations> = operations[Op] extends {
  requestBody: { content: { "application/json": infer T } };
}
  ? T
  : never;

export type PackageRequest = Json<"PaleeWeb.MyPaymentsController.package_requests">["requests"][number];
export type PackageRequestCreated = Json<"PaleeWeb.MyPaymentsController.request_package">;
export type DeskPackageRequest = Json<"PaleeWeb.AdminPackageRequestController.index">["requests"][number];
export type CollectBody = Body<"PaleeWeb.AdminPackageRequestController.collect">;
export type CollectPaymentMethod = CollectBody["payment_method"];

/** The desk methods «Είσπραξη» offers, in the order shown. */
export const COLLECT_METHODS: CollectPaymentMethod[] = ["cash", "card_manual", "bank_transfer", "other"];

const id = (value: string) => encodeURIComponent(value);
const org = (slug: string, path: string) => `/org/${id(slug)}${path}`;

export const myPackageRequestsKey = (slug: string) => ["me", "package-requests", slug] as const;

export function fetchMyPackageRequests(token: string, slug: string) {
  return apiRequest<{ requests: PackageRequest[] }>(org(slug, "/me/package-requests"), { token });
}

/** Asks for a package to pay at the desk; asking again returns the open request. */
export function requestPackage(token: string, slug: string, packageId: string) {
  return apiRequest<PackageRequestCreated>(org(slug, `/me/packages/${id(packageId)}/request`), {
    token,
    method: "POST",
    body: {},
  });
}

export function cancelPackageRequest(token: string, slug: string, requestId: string) {
  return apiRequest<{ request: PackageRequest }>(org(slug, `/me/package-requests/${id(requestId)}/cancel`), {
    token,
    method: "POST",
    body: {},
  });
}

export const deskPackageRequestsKey = (slug: string, locationIds: string | null) =>
  ["admin", "finance", "package-requests", slug, locationIds ?? "all"] as const;

export function fetchDeskPackageRequests(token: string, slug: string, locationIds: string | null) {
  const query = locationIds ? `?${new URLSearchParams({ location_ids: locationIds })}` : "";
  return apiRequest<{ requests: DeskPackageRequest[] }>(org(slug, `/admin/finance/package-requests${query}`), { token });
}

export function collectPackageRequest(token: string, slug: string, requestId: string, body: CollectBody) {
  return apiRequest<Json<"PaleeWeb.AdminPackageRequestController.collect">>(
    org(slug, `/admin/finance/package-requests/${id(requestId)}/collect`),
    { token, method: "POST", body },
  );
}
