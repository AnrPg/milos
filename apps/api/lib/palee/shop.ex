defmodule Palee.Shop do
  @moduledoc """
  The e-shop bounded context (ADR-190): what a gym or independent coach
  sells, its stock, and its orders. Money stays in Finance: an order's
  invoice, payment and refunds are Finance rows with `revenue_stream:
  "shop"` and a source pointing back here (`Shop.Domain.RevenueLineage`).

  This module is the context's public API over its store and pure domain.
  Use cases that cross contexts (Finance, Media, Organizations,
  notifications, audit) live in `Palee.Application.Shop.*`.
  """

  alias Palee.Shop.Domain.{
    OrderLifecycle,
    OrderPricing,
    ProductPolicy,
    RevenueLineage,
    StockLedger,
    StockStatus
  }

  alias Palee.Shop.ShopStore

  # ── Domain vocabulary ───────────────────────────────────────────────────

  defdelegate product_statuses(), to: ProductPolicy, as: :statuses
  defdelegate visibilities(), to: ProductPolicy
  defdelegate product_transition(from, to), to: ProductPolicy, as: :transition
  defdelegate publishable(product, variants), to: ProductPolicy
  defdelegate public_product?(product), to: ProductPolicy, as: :public?
  defdelegate visible_to?(product, viewer), to: ProductPolicy
  defdelegate sellable?(product, channel), to: ProductPolicy
  defdelegate normalize_options(options), to: ProductPolicy
  defdelegate validate_option_values(options, values), to: ProductPolicy
  defdelegate variant_title(options, values), to: ProductPolicy

  defdelegate movement_kinds(), to: StockLedger, as: :kinds
  defdelegate manual_movement_kinds(), to: StockLedger, as: :manual_kinds
  defdelegate adjustment_reasons(), to: StockLedger
  defdelegate recount(level, counted), to: StockLedger
  defdelegate transfer_movements(quantity, from, to), to: StockLedger, as: :transfer
  defdelegate validate_movement(movement), to: StockLedger, as: :validate
  defdelegate stock_statuses(), to: StockStatus, as: :statuses
  defdelegate stock_alert?(previous, current), to: StockStatus, as: :alert?

  defdelegate order_state(order), to: OrderLifecycle, as: :state
  defdelegate order_states(), to: OrderLifecycle, as: :states
  defdelegate order_transition(order, event, facts), to: OrderLifecycle, as: :transition
  defdelegate checkout_mode(mode, facts), to: OrderLifecycle
  defdelegate desk_method(method), to: OrderLifecycle
  defdelegate order_source(value), to: OrderLifecycle, as: :source
  defdelegate desk_methods(), to: OrderLifecycle
  defdelegate online_modes(), to: OrderLifecycle
  defdelegate order_sources(), to: OrderLifecycle, as: :sources
  defdelegate order_expired?(order, now), to: OrderLifecycle, as: :expired?
  defdelegate hold_until(now), to: OrderLifecycle, as: :expires_at

  defdelegate price_cart(items, catalog, opts), to: OrderPricing, as: :price

  defdelegate revenue_stream(), to: RevenueLineage, as: :stream
  defdelegate order_source_type(), to: RevenueLineage, as: :order_source
  defdelegate line_source_type(), to: RevenueLineage, as: :line_source
  defdelegate finance_invoice(order, lines, today), to: RevenueLineage, as: :invoice
  defdelegate finance_payment(order, method, today, extra), to: RevenueLineage, as: :payment
  defdelegate allocate_refund(lines, requested), to: RevenueLineage

  # ── Ports ───────────────────────────────────────────────────────────────

  @doc "The configured payment provider (`Shop.Ports.PaymentProvider`)."
  def payment_provider, do: Application.fetch_env!(:palee, :shop_payment_provider)

  @doc "The configured notifier (`Shop.Ports.ShopNotifier`)."
  def notifier, do: Application.fetch_env!(:palee, :shop_notifier)

  @doc "`%{available, reason, provider}`: whether online card payment can be offered."
  def online_payment(context), do: payment_provider().availability(context)

  # ── Store ───────────────────────────────────────────────────────────────

  @doc "Runs `fun` in one tenant transaction (all or nothing)."
  def transaction(context, fun), do: ShopStore.transaction(context, fun)

  def list_products(context, filters \\ %{}), do: ShopStore.list_products(context, filters)
  def get_product(context, id), do: ShopStore.get_product(context, id)
  def save_product(context, id, attrs), do: ShopStore.save_product(context, id, attrs)
  def list_variants(context, filters), do: ShopStore.list_variants(context, filters)
  def get_variant(context, id), do: ShopStore.get_variant(context, id)
  def save_variant(context, id, attrs), do: ShopStore.save_variant(context, id, attrs)

  @doc """
  Applies ledger movements atomically (`StockLedger` rules, row locks);
  `{:error, {:insufficient_stock, %{variant_id, location_id}}}` refuses the
  whole batch.
  """
  def apply_movements(context, movements), do: ShopStore.apply_movements(context, movements)
  def stock_levels(context, variant_ids), do: ShopStore.stock_levels(context, variant_ids)
  def list_movements(context, filters), do: ShopStore.list_movements(context, filters)

  def get_order(context, id, opts \\ []), do: ShopStore.get_order(context, id, opts)
  def get_order_by_key(context, key), do: ShopStore.get_order_by_key(context, key)
  def insert_order(context, attrs, lines), do: ShopStore.insert_order(context, attrs, lines)
  def update_order(context, id, attrs), do: ShopStore.update_order(context, id, attrs)
  def update_order_line(context, id, attrs), do: ShopStore.update_order_line(context, id, attrs)
  def list_orders(context, filters \\ %{}), do: ShopStore.list_orders(context, filters)

  def units_held(context, user_id, product_ids),
    do: ShopStore.units_held(context, user_id, product_ids)

  @doc """
  The stock status of variants from their levels and recent sales; returns
  `[%{variant, previous, assessment}]` for the ones whose status changed and
  stores the new status.
  """
  def refresh_stock_status(context, variant_ids, now \\ DateTime.utc_now()) do
    variant_ids = Enum.uniq(variant_ids)
    variants = list_variants(context, %{ids: variant_ids})

    sales =
      context
      |> list_movements(%{
        variant_ids: variant_ids,
        kinds: [:sale],
        from: DateTime.add(now, -StockStatus.window_days() * 86_400, :second),
        limit: 50_000
      })
      |> Enum.group_by(& &1.variant_id)

    Enum.flat_map(variants, fn variant ->
      assessment =
        StockStatus.assess(
          variant.stock.available,
          Map.get(sales, variant.id, []),
          variant.low_stock_threshold,
          now
        )

      if variant.track_inventory and assessment.status != variant.stock_status do
        {:ok, _saved} = save_variant(context, variant.id, %{stock_status: assessment.status})
        [%{variant: variant, previous: variant.stock_status, assessment: assessment}]
      else
        []
      end
    end)
  end

  # ── Tenant data lifecycle (ADR-117) ─────────────────────────────────────

  def tenant_data_policy, do: Palee.Shop.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
