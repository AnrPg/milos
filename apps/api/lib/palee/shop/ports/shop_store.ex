defmodule Palee.Shop.Ports.ShopStore do
  @moduledoc """
  Persistence of the shop (ADR-190): catalog, stock ledger and its
  projection, orders. Every callback takes the tenant context first; the
  facade (`Palee.Shop.ShopStore`) opens the tenant session.

  Stock writes are atomic: `apply_movements/2` locks each stock level row
  (`SELECT ... FOR UPDATE`, inserting it first when missing), applies
  `StockLedger.apply_movement/2`, writes the projection and appends the
  ledger rows in one transaction, or nothing.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()
  @type result(value) :: {:ok, value} | {:error, term()}

  @doc "Runs `fun` in one tenant transaction; `{:error, reason}` from it rolls everything back."
  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) :: result(term())

  # Catalog
  @callback list_products(context(), map()) :: [map()]
  @callback get_product(context(), id()) :: map() | nil
  @callback save_product(context(), id() | nil, map()) :: result(map())
  @callback list_variants(context(), map()) :: [map()]
  @callback get_variant(context(), id()) :: map() | nil
  @callback save_variant(context(), id() | nil, map()) :: result(map())

  # Stock
  @callback apply_movements(context(), [map()]) :: result(%{movements: [map()], levels: [map()]})
  @callback stock_levels(context(), [id()]) :: [map()]
  @callback list_movements(context(), map()) :: [map()]

  # Orders
  @callback next_order_number(context()) :: pos_integer()
  @callback get_order_by_key(context(), String.t()) :: map() | nil
  @callback insert_order(context(), map(), [map()]) :: result(map())
  @callback get_order(context(), id(), keyword()) :: map() | nil
  @callback update_order(context(), id(), map()) :: result(map())
  @callback update_order_line(context(), id(), map()) :: result(map())
  @callback list_orders(context(), map()) :: [map()]
  @callback units_held(context(), id(), [id()]) :: %{optional(id()) => non_neg_integer()}

  # Promotion codes («Προώθηση»). `get_promotion_code/3` finds a code by its
  # text or id (`by: :code | :id`); `lock: true` takes its row lock, so
  # counting its redemptions and placing the order are serialised. Every
  # returned code carries `redemptions` (orders, not cancelled, that used it).
  @callback get_promotion_code(context(), String.t(), keyword()) :: map() | nil
  @callback list_promotion_codes(context(), map()) :: [map()]
  @callback save_promotion_code(context(), id() | nil, map()) :: result(map())
end
