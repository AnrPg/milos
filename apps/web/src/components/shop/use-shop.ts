"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "next/navigation";
import { useCallback, useMemo, useSyncExternalStore } from "react";

import {
  cancelShopOrder,
  fetchShopOrder,
  fetchShopProduct,
  fetchShopProducts,
  fetchStorefront,
  placeShopOrder,
  previewShopCart,
  requestBackInStock,
  shopKeys,
  type ShopCartItem,
  type ShopOrderCreate,
  type ShopProductSummary,
} from "@/api/shop";
import { useSession } from "@/components/session-provider";
import { EMPTY_CART, parseCart, serializeCart, type Cart, type PricedVariant } from "@/lib/shop/cart";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * The box whose shop is open: `?box=` (a product card in another box's post
 * links there), else the selected membership.
 */
export function useShopBox() {
  const searchParams = useSearchParams();
  const { membership, memberships, isLoading } = useSelectedMembershipRole();
  const requested = searchParams.get("box");
  const target = requested ? memberships.find((item) => item.organization.slug === requested) ?? null : membership;
  const slug = requested || membership?.organization.slug || null;
  const name = target?.settings?.brand_name?.trim() || target?.organization.name || null;
  return { slug, name, explicit: Boolean(requested), isLoading };
}

/** A shop path that keeps `?box=` when the shop was opened for a named box. */
export function shopHref(path: string, slug: string | null, explicit: boolean, params?: URLSearchParams) {
  const query = new URLSearchParams(params?.toString() ?? "");
  if (explicit && slug) query.set("box", slug);
  const qs = query.toString();
  return `/box/shop${path}${qs ? `?${qs}` : ""}`;
}

function useToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? "";
}

export function useStorefront(slug: string | null) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.storefront(slug ?? ""),
    enabled: Boolean(token && slug),
    queryFn: () => fetchStorefront(token, slug!),
    staleTime: 60_000,
    retry: false,
  });
}

export function useShopProducts(slug: string | null) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.products(slug ?? ""),
    enabled: Boolean(token && slug),
    queryFn: () => fetchShopProducts(token, slug!),
    staleTime: 30_000,
  });
}

export function useShopProduct(slug: string | null, productId: string) {
  const token = useToken();
  const queryClient = useQueryClient();
  return useQuery({
    queryKey: shopKeys.product(slug ?? "", productId),
    enabled: Boolean(token && slug && productId),
    queryFn: () => fetchShopProduct(token, slug!, productId),
    // The grid's card is enough to draw the page while the detail loads.
    placeholderData: () => {
      const list = queryClient.getQueryData<ShopProductSummary[]>(shopKeys.products(slug ?? ""));
      const summary = list?.find((item) => item.id === productId);
      return summary ? { ...summary, description: null, pickup_location_ids: [] } : undefined;
    },
  });
}

export function useShopOrder(slug: string | null, orderId: string) {
  const token = useToken();
  return useQuery({
    queryKey: shopKeys.order(slug ?? "", orderId),
    enabled: Boolean(token && slug && orderId),
    queryFn: () => fetchShopOrder(token, slug!, orderId),
    // Staff mark it ready while the member may be looking at it.
    refetchInterval: 60_000,
  });
}

/** The server's price of the basket; refetched whenever the lines, the pickup branch or the code change. */
export function useCartPreview(slug: string | null, lines: ShopCartItem[], pickupLocationId: string | null, promotionCode: string | null) {
  const token = useToken();
  const signature = JSON.stringify([lines, pickupLocationId, promotionCode]);
  return useQuery({
    queryKey: shopKeys.preview(slug ?? "", signature),
    queryFn: () => previewShopCart(token, slug!, { lines, pickup_location_id: pickupLocationId, promotion_code: promotionCode }),
    retry: false,
    enabled: Boolean(token && slug && lines.length > 0),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
}

export function usePlaceOrder(slug: string | null) {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: ShopOrderCreate) => placeShopOrder(token, slug!, body),
    onSuccess: async (order) => {
      queryClient.setQueryData(shopKeys.order(slug!, order.id), order);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: shopKeys.storefront(slug!) }),
        queryClient.invalidateQueries({ queryKey: shopKeys.products(slug!) }),
        // The order's invoice lands in Εγώ › Πληρωμές › Συναλλαγές.
        queryClient.invalidateQueries({ queryKey: ["me", "billing"] }),
      ]);
    },
  });
}

export function useCancelOrder(slug: string | null) {
  const token = useToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (orderId: string) => cancelShopOrder(token, slug!, orderId),
    onSuccess: async (order) => {
      queryClient.setQueryData(shopKeys.order(slug!, order.id), order);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: shopKeys.storefront(slug!) }),
        queryClient.invalidateQueries({ queryKey: ["me", "billing"] }),
      ]);
    },
  });
}

export function useBackInStock(slug: string | null) {
  const token = useToken();
  return useMutation({ mutationFn: (variantId: string) => requestBackInStock(token, slug!, variantId) });
}

/** The loaded catalogue as prices per variant, for the cart's totals. */
export function usePricedCatalog(products: ShopProductSummary[] | undefined) {
  return useMemo(() => {
    const map = new Map<string, PricedVariant>();
    for (const product of products ?? []) {
      for (const variant of product.variants) {
        map.set(variant.id, {
          productId: product.id,
          unitPriceCents: variant.price_cents,
          memberDiscountApplies: product.member_discount_applies,
          currency: variant.currency,
        });
      }
    }
    return map;
  }, [products]);
}

// The cart: one per box, kept in the browser ----------------------------------

const CART_KEY = (slug: string) => `palee:shop-cart:${slug}`;
const listeners = new Set<() => void>();
const snapshots = new Map<string, { raw: string | null; cart: Cart }>();

function readCart(slug: string): Cart {
  let raw: string | null = null;
  try {
    raw = window.localStorage.getItem(CART_KEY(slug));
  } catch {
    raw = null;
  }
  const cached = snapshots.get(slug);
  if (cached && cached.raw === raw) return cached.cart;
  const cart = parseCart(raw);
  snapshots.set(slug, { raw, cart });
  return cart;
}

function writeCart(slug: string, cart: Cart) {
  try {
    if (cart.lines.length === 0) window.localStorage.removeItem(CART_KEY(slug));
    else window.localStorage.setItem(CART_KEY(slug), serializeCart(cart));
  } catch {
    // Private mode: the cart lives for this page only.
    snapshots.set(slug, { raw: null, cart });
  }
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  const onStorage = (event: StorageEvent) => {
    if (event.key?.startsWith("palee:shop-cart:")) listener();
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", onStorage);
  };
}

export function useCart(slug: string | null) {
  const cart = useSyncExternalStore(
    subscribe,
    () => (slug ? readCart(slug) : EMPTY_CART),
    () => EMPTY_CART,
  );
  const update = useCallback(
    (change: (current: Cart) => Cart) => {
      if (!slug) return;
      writeCart(slug, change(readCart(slug)));
    },
    [slug],
  );
  return { cart, update };
}
