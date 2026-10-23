defmodule Palee.Infrastructure.Shop.EctoShopReportStore do
  @moduledoc """
  Postgres adapter of `Palee.Shop.Ports.ShopReportStore` (ADR-192).

  Every read aggregates in SQL and names the tenant twice: row level
  security on every table, and an explicit `organization_id = $1` predicate,
  so a connection that bypasses RLS (a superuser in development) still reads
  one business only, and the planner can use the per-business indexes
  (`shop_orders_paid_at_index`, `membership_payments_paid_stream_index`).

  Timestamps are stored as UTC `timestamp` columns; gym-local days are
  `(ts AT TIME ZONE 'UTC') AT TIME ZONE zone`, while the window itself is
  given as UTC bounds so the range predicate stays indexable.
  """

  @behaviour Palee.Shop.Ports.ShopReportStore

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @paid_statuses "('paid', 'partially_refunded', 'refunded')"

  # $1 organization, $2/$3 UTC bounds, $4 zone, $5 branches (NULL = all).
  # Every statement names all five (Postgres must type each parameter).
  @paid_orders """
  o.organization_id = $1 AND $4::text IS NOT NULL
  AND o.paid_at >= $2::timestamp AND o.paid_at < $3::timestamp
  AND o.payment_status IN #{@paid_statuses}
  AND ($5::uuid[] IS NULL OR o.pickup_location_id = ANY($5::uuid[]))
  """

  @local_day "((o.paid_at AT TIME ZONE 'UTC') AT TIME ZONE $4::text)::date"

  @impl true
  def sales_by_day(filters) do
    """
    SELECT #{@local_day} AS day, o.currency, count(*)::bigint,
           COALESCE(sum(o.total_cents), 0)::bigint, COALESCE(sum(o.refunded_cents), 0)::bigint
    FROM shop_orders o
    WHERE #{@paid_orders}
    GROUP BY 1, 2
    ORDER BY 1, 2
    """
    |> query(filters)
    |> Enum.map(fn [day, currency, orders, gross, refunded] ->
      %{
        day: day,
        currency: currency,
        orders: orders,
        gross_cents: gross,
        refunded_cents: refunded
      }
    end)
  end

  @order_totals "count(*)::bigint, COALESCE(sum(o.total_cents), 0)::bigint, COALESCE(sum(o.refunded_cents), 0)::bigint"

  @impl true
  def order_groups(filters, :channel), do: simple_groups(filters, "o.channel", :channel)

  def order_groups(filters, :location_id),
    do: simple_groups(filters, "o.pickup_location_id", :location_id, &uuid/1)

  def order_groups(filters, :promotion_code) do
    """
    SELECT upper(o.promotion_code), #{@order_totals}
    FROM shop_orders o
    WHERE #{@paid_orders} AND o.promotion_code IS NOT NULL AND o.promotion_code <> ''
    GROUP BY 1
    """
    |> query(filters)
    |> Enum.map(&totals_row(&1, :promotion_code))
  end

  def order_groups(filters, :campaign_id) do
    """
    SELECT code.promotion_campaign_id, #{@order_totals}
    FROM shop_orders o
    JOIN promotion_codes code
      ON code.organization_id = o.organization_id AND upper(code.code) = upper(o.promotion_code)
    WHERE #{@paid_orders} AND o.promotion_code IS NOT NULL
    GROUP BY 1
    """
    |> query(filters)
    |> Enum.map(&totals_row(&1, :campaign_id, fn value -> uuid(value) end))
  end

  def order_groups(filters, :source) do
    """
    SELECT o.source, o.source_ref_id,
           (o.promotion_code IS NOT NULL AND o.promotion_code <> ''), #{@order_totals}
    FROM shop_orders o
    WHERE #{@paid_orders}
    GROUP BY 1, 2, 3
    """
    |> query(filters)
    |> Enum.map(fn [source, ref, with_code, orders, gross, refunded] ->
      %{
        source: source,
        source_ref_id: uuid(ref),
        with_code: with_code,
        orders: orders,
        gross_cents: gross,
        refunded_cents: refunded
      }
    end)
  end

  defp simple_groups(filters, column, key, cast \\ & &1) do
    """
    SELECT #{column}, #{@order_totals}
    FROM shop_orders o
    WHERE #{@paid_orders}
    GROUP BY 1
    """
    |> query(filters)
    |> Enum.map(&totals_row(&1, key, cast))
  end

  defp totals_row([value, orders, gross, refunded], key, cast \\ & &1) do
    %{key => cast.(value), orders: orders, gross_cents: gross, refunded_cents: refunded}
  end

  @impl true
  def line_groups(filters) do
    """
    SELECT l.product_id, max(l.product_title), l.variant_id, max(l.variant_title),
           sum(l.quantity)::bigint, sum(l.refunded_quantity)::bigint,
           sum(l.total_cents)::bigint, sum(l.refunded_cents)::bigint,
           COALESCE(sum(l.total_cents - l.refunded_cents)
             FILTER (WHERE l.cost_price_cents IS NOT NULL), 0)::bigint,
           COALESCE(sum((l.quantity - l.refunded_quantity) * l.cost_price_cents::bigint)
             FILTER (WHERE l.cost_price_cents IS NOT NULL), 0)::bigint
    FROM shop_order_lines l
    JOIN shop_orders o ON o.id = l.order_id AND o.organization_id = l.organization_id
    WHERE #{@paid_orders}
    GROUP BY l.product_id, l.variant_id
    """
    |> query(filters)
    |> Enum.map(fn [
                     product,
                     product_name,
                     variant,
                     variant_name,
                     units,
                     refunded_units,
                     revenue,
                     refunded,
                     costed,
                     cost
                   ] ->
      %{
        product_id: uuid(product),
        product_name: product_name,
        variant_id: uuid(variant),
        variant_name: variant_name,
        units: units,
        refunded_units: refunded_units,
        revenue_cents: revenue,
        refunded_cents: refunded,
        costed_revenue_cents: costed,
        cost_cents: cost
      }
    end)
  end

  @impl true
  def stock(filters) do
    """
    WITH sold AS (
      SELECT m.variant_id, m.location_id,
             (COALESCE(sum(-m.quantity) FILTER (WHERE m.kind = 'sale'), 0)
              - COALESCE(sum(m.quantity) FILTER (WHERE m.kind = 'refund_restock'), 0))::bigint AS units
      FROM shop_stock_movements m
      WHERE m.organization_id = $1
        AND m.occurred_at >= $2::timestamp AND m.occurred_at < $3::timestamp
        AND m.kind IN ('sale', 'refund_restock')
      GROUP BY m.variant_id, m.location_id
    )
    SELECT v.id, p.id, p.title, v.title, s.location_id, s.on_hand, s.reserved,
           v.cost_price_cents, v.low_stock_threshold, COALESCE(sold.units, 0)::bigint,
           ($4::text IS NOT NULL)
    FROM shop_stock_levels s
    JOIN shop_variants v ON v.id = s.variant_id AND v.organization_id = s.organization_id
    JOIN shop_products p ON p.id = v.product_id AND p.organization_id = v.organization_id
    LEFT JOIN sold ON sold.variant_id = s.variant_id
      AND sold.location_id IS NOT DISTINCT FROM s.location_id
    WHERE s.organization_id = $1
      AND v.archived_at IS NULL AND p.archived_at IS NULL AND v.track_inventory
      AND ($5::uuid[] IS NULL OR s.location_id IS NULL OR s.location_id = ANY($5::uuid[]))
    """
    |> query(filters)
    |> Enum.map(fn [
                     variant,
                     product,
                     product_name,
                     variant_name,
                     location,
                     on_hand,
                     reserved,
                     cost,
                     threshold,
                     sold,
                     _zone?
                   ] ->
      %{
        variant_id: uuid(variant),
        product_id: uuid(product),
        product_name: product_name,
        variant_name: variant_name,
        location_id: uuid(location),
        on_hand: on_hand,
        reserved: reserved,
        unit_cost_cents: cost,
        low_stock_threshold: threshold,
        sold_units: sold
      }
    end)
  end

  @impl true
  def pricing_inputs(filters) do
    variants = pricing_variants(filters)
    ids = Enum.map(variants, &Ecto.UUID.dump!(&1.variant_id))
    periods = ids |> price_periods(filters) |> Enum.group_by(& &1.variant_id)
    discounts = ids |> discount_groups(filters) |> Enum.group_by(& &1.variant_id)

    Enum.map(variants, fn variant ->
      variant_periods = Map.get(periods, variant.variant_id, [])
      variant_discounts = Map.get(discounts, variant.variant_id, [])

      Map.merge(variant, %{
        periods: Enum.map(variant_periods, &Map.delete(&1, :variant_id)),
        price_points: Enum.map(variant_periods, &Map.take(&1, [:price_cents, :units, :days])),
        promo: Enum.find_value(variant_discounts, &(&1.discounted && &1.sales)),
        full_price: Enum.find_value(variant_discounts, &(!&1.discounted && &1.sales))
      })
    end)
  end

  defp pricing_variants(filters) do
    """
    SELECT v.id, p.id, p.title, v.title, p.category, v.price_cents, v.cost_price_cents,
           COALESCE(sum(s.on_hand), 0)::bigint, ($2::timestamp < $3::timestamp), ($4::text IS NOT NULL)
    FROM shop_variants v
    JOIN shop_products p ON p.id = v.product_id AND p.organization_id = v.organization_id
    LEFT JOIN shop_stock_levels s ON s.variant_id = v.id AND s.organization_id = v.organization_id
      AND ($5::uuid[] IS NULL OR s.location_id IS NULL OR s.location_id = ANY($5::uuid[]))
    WHERE v.organization_id = $1 AND v.archived_at IS NULL AND p.archived_at IS NULL
    GROUP BY v.id, p.id
    """
    |> query(filters)
    |> Enum.map(fn [
                     variant,
                     product,
                     product_name,
                     variant_name,
                     category,
                     price,
                     cost,
                     on_hand,
                     _window?,
                     _zone?
                   ] ->
      %{
        variant_id: uuid(variant),
        product_id: uuid(product),
        product_name: product_name,
        variant_name: variant_name,
        category: category,
        price_cents: price,
        cost_cents: cost,
        on_hand: on_hand
      }
    end)
  end

  # The window cut at every price change of the ledger, with the units sold
  # (net of refunds) while each price held. Rows that only changed the cost
  # keep the price and merge into one period.
  defp price_periods([], _filters), do: []

  defp price_periods(variant_ids, filters) do
    """
    WITH ledger AS (
      SELECT c.variant_id, c.price_cents, c.changed_at,
             lag(c.price_cents) OVER (PARTITION BY c.variant_id ORDER BY c.changed_at, c.inserted_at) AS previous
      FROM shop_variant_price_changes c
      WHERE c.organization_id = $1 AND c.variant_id = ANY($6::uuid[]) AND c.changed_at < $3::timestamp
    ), changes AS (
      SELECT variant_id, price_cents, changed_at,
             lead(changed_at) OVER (PARTITION BY variant_id ORDER BY changed_at) AS next_at
      FROM ledger WHERE previous IS NULL OR previous <> price_cents
    ), periods AS (
      SELECT variant_id, price_cents,
             GREATEST(changed_at, $2::timestamp) AS starts_at,
             LEAST(COALESCE(next_at, $3::timestamp), $3::timestamp) AS ends_at
      FROM changes
    )
    SELECT pr.variant_id, pr.price_cents,
           ((pr.starts_at AT TIME ZONE 'UTC') AT TIME ZONE $4::text)::date,
           ((pr.ends_at AT TIME ZONE 'UTC') AT TIME ZONE $4::text)::date,
           GREATEST(ceil(extract(epoch FROM pr.ends_at - pr.starts_at) / 86400.0), 1)::bigint,
           COALESCE((
             SELECT sum(l.quantity - l.refunded_quantity)
             FROM shop_order_lines l
             JOIN shop_orders o ON o.id = l.order_id AND o.organization_id = l.organization_id
             WHERE l.variant_id = pr.variant_id AND l.organization_id = $1
               AND o.paid_at >= pr.starts_at AND o.paid_at < pr.ends_at
               AND o.payment_status IN #{@paid_statuses}
               AND ($5::uuid[] IS NULL OR o.pickup_location_id = ANY($5::uuid[]))
           ), 0)::bigint
    FROM periods pr
    WHERE pr.ends_at > pr.starts_at
    ORDER BY pr.variant_id, pr.starts_at
    """
    |> query(filters, [variant_ids])
    |> Enum.map(fn [variant, price, from, to, days, units] ->
      %{
        variant_id: uuid(variant),
        price_cents: price,
        from: from,
        to: to,
        days: days,
        units: units
      }
    end)
  end

  # Sales with a promotion code or a line discount against full-price ones.
  defp discount_groups([], _filters), do: []

  defp discount_groups(variant_ids, filters) do
    """
    SELECT l.variant_id,
           (o.promotion_code IS NOT NULL AND o.promotion_code <> '') OR l.discount_cents > 0,
           sum(l.quantity - l.refunded_quantity)::bigint, count(DISTINCT o.id)::bigint,
           sum(l.unit_price_cents::bigint * l.quantity)::bigint, sum(l.discount_cents)::bigint
    FROM shop_order_lines l
    JOIN shop_orders o ON o.id = l.order_id AND o.organization_id = l.organization_id
    WHERE #{@paid_orders} AND l.variant_id = ANY($6::uuid[])
    GROUP BY 1, 2
    """
    |> query(filters, [variant_ids])
    |> Enum.map(fn [variant, discounted, units, orders, list, discount] ->
      %{
        variant_id: uuid(variant),
        discounted: discounted,
        sales: %{units: units, orders: orders, list_cents: list, discount_cents: discount}
      }
    end)
  end

  @impl true
  def pricing_targets do
    %{rows: rows} =
      Repo.query!(
        "SELECT category, target_margin_bp FROM shop_pricing_targets WHERE organization_id = $1",
        [organization_id!()]
      )

    Map.new(rows, fn [category, bp] -> {category, bp} end)
  end

  @impl true
  def put_pricing_target(category, nil, _user_id) do
    Repo.query!(
      "DELETE FROM shop_pricing_targets WHERE organization_id = $1 AND category IS NOT DISTINCT FROM $2",
      [organization_id!(), category]
    )

    :ok
  end

  def put_pricing_target(category, target_bp, user_id) when is_integer(target_bp) do
    Repo.query!(
      """
      INSERT INTO shop_pricing_targets
        (id, organization_id, category, target_margin_bp, updated_by_id, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now())
      ON CONFLICT (organization_id, category)
      DO UPDATE SET target_margin_bp = EXCLUDED.target_margin_bp,
                    updated_by_id = EXCLUDED.updated_by_id, updated_at = now()
      """,
      [organization_id!(), category, target_bp, dump(user_id)]
    )

    :ok
  rescue
    error in Postgrex.Error -> {:error, error.postgres[:code] || :invalid_target}
  end

  @impl true
  def reconciliation_figures(filters) do
    %{
      orders: keyed(reconciliation_orders(filters)),
      invoice_lines: keyed(reconciliation_lines(filters)),
      payments: keyed(reconciliation_payments(filters))
    }
  end

  defp reconciliation_orders(filters) do
    """
    SELECT #{@local_day}, o.currency, sum(o.total_cents - o.refunded_cents)::bigint
    FROM shop_orders o
    WHERE #{@paid_orders}
    GROUP BY 1, 2
    """
    |> query(filters)
  end

  # Finance's shop lines of the window's paid orders (by the order's paid
  # day), minus the refunds of the payments of those invoices.
  defp reconciliation_lines(filters) do
    """
    WITH orders AS (
      SELECT o.id, o.finance_invoice_id, #{@local_day} AS day
      FROM shop_orders o
      WHERE #{@paid_orders}
    ), lines AS (
      SELECT ord.day, line.finance_invoice_id, invoice.currency, sum(line.total_cents) AS cents
      FROM finance_invoice_lines line
      JOIN finance_invoices invoice ON invoice.id = line.finance_invoice_id
      JOIN shop_order_lines order_line ON order_line.id = line.source_id
      JOIN orders ord ON ord.id = order_line.order_id
      WHERE line.organization_id = $1 AND line.revenue_stream = 'shop'
        AND line.source_type = 'shop_order_line'
        AND invoice.deleted_at IS NULL AND invoice.voided_at IS NULL
      GROUP BY 1, 2, 3
    ), refunds AS (
      SELECT payment.finance_invoice_id, sum(reversal.amount_cents) AS cents
      FROM finance_payment_reversals reversal
      JOIN membership_payments payment ON payment.id = reversal.membership_payment_id
      WHERE reversal.organization_id = $1 AND reversal.revenue_stream = 'shop'
        AND reversal.deleted_at IS NULL AND payment.deleted_at IS NULL
        AND payment.finance_invoice_id IN (SELECT finance_invoice_id FROM lines)
      GROUP BY 1
    )
    SELECT lines.day, lines.currency, sum(lines.cents - COALESCE(refunds.cents, 0))::bigint
    FROM lines LEFT JOIN refunds ON refunds.finance_invoice_id = lines.finance_invoice_id
    GROUP BY 1, 2
    """
    |> query(filters)
  end

  # Finance's shop payments of the window's business days (`paid_on`) minus
  # their refunds. Under a branch filter, payments of orders at the branch.
  defp reconciliation_payments(filters) do
    """
    SELECT p.paid_on, p.currency,
           sum(p.amount_cents - COALESCE((
             SELECT sum(r.amount_cents) FROM finance_payment_reversals r
             WHERE r.membership_payment_id = p.id AND r.deleted_at IS NULL
           ), 0))::bigint
    FROM membership_payments p
    WHERE p.organization_id = $1 AND p.revenue_stream = 'shop'
      AND p.payment_status IN ('paid', 'refunded') AND p.deleted_at IS NULL
      AND p.paid_on >= ((($2::timestamp) AT TIME ZONE 'UTC') AT TIME ZONE $4::text)::date
      AND p.paid_on < ((($3::timestamp) AT TIME ZONE 'UTC') AT TIME ZONE $4::text)::date
      AND ($5::uuid[] IS NULL OR EXISTS (
        SELECT 1 FROM shop_orders o
        WHERE o.id = p.source_id AND o.pickup_location_id = ANY($5::uuid[])))
    GROUP BY 1, 2
    """
    |> query(filters)
  end

  defp keyed(rows), do: Map.new(rows, fn [day, currency, cents] -> {{day, currency}, cents} end)

  ## Plumbing

  defp query(sql, filters, extra \\ []) do
    params = [
      organization_id!(),
      DateTime.to_naive(filters.from_at),
      DateTime.to_naive(filters.to_at),
      filters.zone,
      location_param(filters[:location_ids])
    ]

    %{rows: rows} = Repo.query!(sql, params ++ extra)
    rows
  end

  defp location_param(nil), do: nil
  defp location_param(ids) when is_list(ids), do: Enum.map(ids, &Ecto.UUID.dump!/1)

  defp organization_id! do
    case RepoContext.current_setting("app.organization_id") do
      id when is_binary(id) -> Ecto.UUID.dump!(id)
      _missing -> raise ArgumentError, "shop reports need a tenant scope"
    end
  end

  defp dump(nil), do: nil
  defp dump(id), do: Ecto.UUID.dump!(id)

  defp uuid(nil), do: nil
  defp uuid(<<_::128>> = raw), do: Ecto.UUID.load!(raw)
  defp uuid(value) when is_binary(value), do: value
end
