defmodule Palee.Shop.ShopStore do
  @moduledoc false
  @behaviour Palee.Shop.Ports.ShopStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :shop_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def list_products(context, filters), do: tenant_call(context, :list_products, [filters])
  @impl true
  def get_product(context, id), do: tenant_call(context, :get_product, [id])
  @impl true
  def save_product(context, id, attrs), do: tenant_call(context, :save_product, [id, attrs])
  @impl true
  def list_variants(context, filters), do: tenant_call(context, :list_variants, [filters])
  @impl true
  def get_variant(context, id), do: tenant_call(context, :get_variant, [id])
  @impl true
  def save_variant(context, id, attrs), do: tenant_call(context, :save_variant, [id, attrs])

  @impl true
  def apply_movements(context, movements),
    do: tenant_call(context, :apply_movements, [movements])

  @impl true
  def stock_levels(context, variant_ids), do: tenant_call(context, :stock_levels, [variant_ids])
  @impl true
  def list_movements(context, filters), do: tenant_call(context, :list_movements, [filters])

  @impl true
  def next_order_number(context), do: tenant_call(context, :next_order_number, [])
  @impl true
  def get_order_by_key(context, key), do: tenant_call(context, :get_order_by_key, [key])
  @impl true
  def insert_order(context, attrs, lines), do: tenant_call(context, :insert_order, [attrs, lines])
  @impl true
  def get_order(context, id, opts \\ []), do: tenant_call(context, :get_order, [id, opts])
  @impl true
  def update_order(context, id, attrs), do: tenant_call(context, :update_order, [id, attrs])
  @impl true
  def update_order_line(context, id, attrs),
    do: tenant_call(context, :update_order_line, [id, attrs])

  @impl true
  def list_orders(context, filters), do: tenant_call(context, :list_orders, [filters])
  @impl true
  def order_counts(context, filters), do: tenant_call(context, :order_counts, [filters])
  @impl true
  def units_held(context, user_id, product_ids),
    do: tenant_call(context, :units_held, [user_id, product_ids])

  @impl true
  def get_promotion_code(context, code, opts \\ []),
    do: tenant_call(context, :get_promotion_code, [code, opts])

  @impl true
  def list_promotion_codes(context, filters),
    do: tenant_call(context, :list_promotion_codes, [filters])

  @impl true
  def save_promotion_code(context, id, attrs),
    do: tenant_call(context, :save_promotion_code, [id, attrs])
end
