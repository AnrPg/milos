"use client";

import { LoadingLine, NotIncluded } from "@/components/client/ClientPage";
import { hasFeature, type ClientFeature } from "@/components/client/entitlement";
import { useClientEntitlement } from "@/components/client/use-client-entitlement";

/**
 * Renders its children only when the package includes the feature. If the
 * entitlement cannot be read the page still loads and the API's 403 decides.
 */
export function FeatureGate({ feature, children }: { feature: ClientFeature; children: React.ReactNode }) {
  const { entitlement, isLoading, isError } = useClientEntitlement();
  if (isLoading) return <LoadingLine />;
  if (!isError && !hasFeature(entitlement, feature)) return <NotIncluded />;
  return <>{children}</>;
}
