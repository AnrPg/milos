"use client";

import { useCallback, useMemo } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { BUSINESS_NOT_ACTIVATED_EVENT } from "@/api/client";
import { fetchFinanceMember } from "@/api/finance";
import { fetchStaffGroups } from "@/api/admin-community";
import {
  actOnShopOrder,
  createPosSale,
  createShopProduct,
  fetchShopMovements,
  fetchShopOrder,
  fetchShopOrders,
  fetchShopPaymentMethods,
  fetchShopProduct,
  fetchShopProducts,
  fetchShopReport,
  fetchShopStock,
  promoteShopProduct,
  recordShopMovement,
  setShopProductStatus,
  SHOP_KEY,
  updateShopProduct,
  type OrderAction,
  type PosSaleInput,
  type PromoteInput,
  type ReportWindow,
  type ShopMovementInput,
  type ShopOrderStatus,
  type ShopProduct,
  type ShopProductInput,
  type ShopProductStatus,
  type ShopReportName,
} from "@/api/shop";
import { useSession } from "@/components/session-provider";
import { memberDiscountPercent, unpaidBalanceCents } from "@/lib/shop/console";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

// Data access of the shop console. Components read and write through these
// hooks only; every list follows the page branch filter (`locationIds`).

function useToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/**
 * Who may do what in «Κατάστημα» (`PaleeWeb.RouteCapabilities`):
 * `manage_shop` runs the catalog, stock and refunds (refunds also need
 * `take_payments`); `sell_shop` handles orders and the Ταμείο;
 * «Αναλυτικά» opens to `view_business_analytics` too (ADR-192 §4).
 */
export function useShopAccess() {
  const { membership, isLoading } = useSelectedMembershipRole();
  const manage = can(membership, "manage_shop");
  const sell = manage || can(membership, "sell_shop");
  const analytics = manage || can(membership, "view_business_analytics");
  return {
    isLoading,
    manage,
    analytics,
    sell,
    refund: manage && can(membership, "take_payments"),
    any: sell || analytics,
    /** ADR-184: a demo business builds its catalog but cannot publish or sell. */
    demo: membership?.organization?.activation === "demo",
  };
}

/** Opens the existing «Ενεργοποίηση από την ομάδα Palee» notice instead of calling the API. */
export function useDemoGate() {
  const { demo } = useShopAccess();
  return useCallback(
    (run: () => void) => {
      if (demo) {
        window.dispatchEvent(new CustomEvent(BUSINESS_NOT_ACTIVATED_EVENT));
        return;
      }
      run();
    },
    [demo],
  );
}

export const shopKeys = {
  products: (filter: string, locationIds?: string) => [...SHOP_KEY, "products", filter, locationIds ?? "all"] as const,
  product: (id: string) => [...SHOP_KEY, "product", id] as const,
  orders: (status: string, locationIds?: string) => [...SHOP_KEY, "orders", status, locationIds ?? "all"] as const,
  order: (id: string) => [...SHOP_KEY, "order", id] as const,
  stock: (attention: boolean, locationIds?: string) => [...SHOP_KEY, "stock", attention, locationIds ?? "all"] as const,
  movements: (variantId: string | null, locationIds?: string) => [...SHOP_KEY, "movements", variantId ?? "all", locationIds ?? "all"] as const,
  report: (name: ShopReportName, window: ReportWindow) => [...SHOP_KEY, "report", name, window.days ?? 0, window.locationIds ?? "all"] as const,
};

export function useShopProducts(filter: ShopProductStatus | "low_stock" | "all", locationIds?: string) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.products(filter, locationIds),
    enabled: Boolean(token),
    queryFn: () => fetchShopProducts(token!, { status: filter === "all" ? undefined : filter, locationIds }),
  });
}

export function useShopProduct(productId: string | null) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.product(productId ?? "new"),
    enabled: Boolean(token && productId),
    queryFn: () => fetchShopProduct(token!, productId!),
  });
}

function useInvalidateShop() {
  const queryClient = useQueryClient();
  return useCallback(() => queryClient.invalidateQueries({ queryKey: SHOP_KEY }), [queryClient]);
}

/** Creates a draft, or saves the product and its variants against `previous` (what was loaded). */
export function useSaveProduct(previous: ShopProduct | null | undefined) {
  const token = useToken();
  const invalidate = useInvalidateShop();
  return useMutation({
    mutationFn: (input: ShopProductInput) => (previous ? updateShopProduct(token!, previous.id, input, previous) : createShopProduct(token!, input)),
    onSuccess: () => void invalidate(),
  });
}

export function useProductStatus(productId: string | null) {
  const token = useToken();
  const invalidate = useInvalidateShop();
  return useMutation({
    mutationFn: (status: ShopProductStatus) => setShopProductStatus(token!, productId!, status),
    onSuccess: () => void invalidate(),
  });
}

export function usePromoteProduct(productId: string) {
  const token = useToken();
  return useMutation({ mutationFn: (input: PromoteInput) => promoteShopProduct(token!, productId, input) });
}

/** The box's live member groups, for «Προώθηση» to a group. */
export function useMemberGroups(enabled: boolean) {
  const token = useToken();
  return useQuery({
    queryKey: ["admin", "community", "groups"],
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchStaffGroups(token!),
    select: (data) => data.live ?? [],
  });
}

export function useShopOrders(status: ShopOrderStatus, locationIds?: string) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.orders(status, locationIds),
    enabled: Boolean(token),
    queryFn: () => fetchShopOrders(token!, { status, locationIds }),
  });
}

/** The latest paid shop sales, for the finance overview's shop rows. */
export function useRecentShopSales(locationIds: string | undefined, enabled: boolean) {
  const token = useToken();
  return useQuery({
    queryKey: [...SHOP_KEY, "recent-sales", locationIds ?? "all"],
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchShopOrders(token!, { paid: true, locationIds, limit: 5 }),
    select: (data) => data.orders,
    retry: false,
  });
}

export function useShopOrder(orderId: string | null) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.order(orderId ?? "none"),
    enabled: Boolean(token && orderId),
    queryFn: () => fetchShopOrder(token!, orderId!),
  });
}

export function useOrderAction(orderId: string) {
  const token = useToken();
  const invalidate = useInvalidateShop();
  return useMutation({
    mutationFn: (change: OrderAction) => actOnShopOrder(token!, orderId, change),
    onSuccess: () => void invalidate(),
  });
}

export function useShopStock(attention: boolean, locationIds?: string) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.stock(attention, locationIds),
    enabled: Boolean(token),
    queryFn: () => fetchShopStock(token!, { attention, locationIds }),
    select: (data) => data.items,
  });
}

export function useShopMovements(variantId: string | null, locationIds?: string, titles?: { product: string; variant?: string | null }) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.movements(variantId, locationIds),
    enabled: Boolean(token),
    queryFn: () => fetchShopMovements(token!, { variantId: variantId ?? undefined, locationIds, limit: 30, titles }),
    select: (data) => data.movements,
  });
}

export function useRecordMovement() {
  const token = useToken();
  const invalidate = useInvalidateShop();
  return useMutation({
    mutationFn: (input: ShopMovementInput) => recordShopMovement(token!, input),
    onSuccess: () => void invalidate(),
  });
}

export function usePosSale() {
  const token = useToken();
  const invalidate = useInvalidateShop();
  return useMutation({
    mutationFn: (input: PosSaleInput) => createPosSale(token!, input),
    onSuccess: () => void invalidate(),
  });
}

/** Which ways to pay the payment adapter offers; online card stays off until a provider exists. */
export function useShopPaymentMethods() {
  const token = useToken();
  return useQuery({
    queryKey: [...SHOP_KEY, "payment-methods"],
    enabled: Boolean(token),
    queryFn: () => fetchShopPaymentMethods(),
    staleTime: 5 * 60_000,
    retry: false,
  });
}

/** The member the desk is selling to: unpaid balance and package discount. */
export function useDeskMember(userId: string | null) {
  const token = useToken();
  const query = useQuery({
    queryKey: ["admin", "finance", "member", userId ?? "none"],
    enabled: Boolean(token && userId),
    queryFn: () => fetchFinanceMember(token!, userId!),
  });
  const summary = useMemo(() => {
    if (!query.data) return null;
    return {
      unpaidCents: unpaidBalanceCents(query.data.invoices ?? []),
      discountPercent: memberDiscountPercent(query.data.package_subscriptions ?? []),
    };
  }, [query.data]);
  return { ...query, summary };
}

export function useShopReport<Name extends ShopReportName>(name: Name, window: ReportWindow, enabled = true) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.report(name, window),
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchShopReport(token!, name, window),
    retry: false,
  });
}
