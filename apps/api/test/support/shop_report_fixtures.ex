defmodule Palee.TestSupport.ShopReportFixtures do
  @moduledoc """
  Raw shop and shop-stream Finance rows for the ADR-192 report tests, written
  the way ADR-190's writers lay them out (RevenueLineage), so the reports and
  the reconciliation are tested against the stored shape, not a writer.
  """

  alias Palee.Repo

  def uuid, do: Ecto.UUID.generate()

  defp dump(nil), do: nil
  defp dump(id), do: Ecto.UUID.dump!(id)

  defp now, do: DateTime.utc_now() |> DateTime.to_naive()

  def product(org, attrs \\ %{}) do
    id = uuid()

    insert!("shop_products", %{
      id: dump(id),
      organization_id: dump(org),
      title: Map.get(attrs, :title, "Shaker"),
      category: Map.get(attrs, :category, "gear"),
      status: "published",
      inserted_at: now(),
      updated_at: now()
    })

    id
  end

  def variant(org, product_id, attrs \\ %{}) do
    id = uuid()

    insert!("shop_variants", %{
      id: dump(id),
      organization_id: dump(org),
      product_id: dump(product_id),
      title: Map.get(attrs, :title, "Black"),
      price_cents: Map.get(attrs, :price_cents, 1_500),
      cost_price_cents: Map.get(attrs, :cost_price_cents),
      low_stock_threshold: Map.get(attrs, :low_stock_threshold),
      inserted_at: Map.get(attrs, :inserted_at, now()),
      updated_at: now()
    })

    id
  end

  def set_price(variant_id, price_cents) do
    Repo.query!("UPDATE shop_variants SET price_cents = $2, updated_at = now() WHERE id = $1", [
      dump(variant_id),
      price_cents
    ])
  end

  @doc """
  Moves the variant's price-ledger rows (oldest first) to `times`. The
  ledger is append-only, so this bypasses triggers for the one statement:
  tests need history in the past, the trigger writes the wall clock.
  """
  def backdate_prices(variant_id, times) do
    %{rows: ids} =
      Repo.query!(
        "SELECT id FROM shop_variant_price_changes WHERE variant_id = $1 ORDER BY changed_at, inserted_at",
        [dump(variant_id)]
      )

    Repo.query!("SET session_replication_role = replica")

    ids
    |> Enum.zip(times)
    |> Enum.each(fn {[id], at} ->
      Repo.query!("UPDATE shop_variant_price_changes SET changed_at = $2 WHERE id = $1", [id, at])
    end)

    Repo.query!("SET session_replication_role = DEFAULT")
  end

  def stock(org, variant_id, location_id, on_hand, reserved \\ 0) do
    insert!("shop_stock_levels", %{
      id: dump(uuid()),
      organization_id: dump(org),
      variant_id: dump(variant_id),
      location_id: dump(location_id),
      on_hand: on_hand,
      reserved: reserved,
      inserted_at: now(),
      updated_at: now()
    })
  end

  def movement(org, variant_id, location_id, kind, quantity, %DateTime{} = at) do
    insert!("shop_stock_movements", %{
      id: dump(uuid()),
      organization_id: dump(org),
      variant_id: dump(variant_id),
      location_id: dump(location_id),
      kind: kind,
      quantity: quantity,
      occurred_at: DateTime.to_naive(at),
      inserted_at: now()
    })
  end

  @doc """
  A paid order with its lines and, unless `finance: false`, its Finance
  invoice, shop lines and payment (one per order, as ADR-190 writes them).
  `lines` are `%{product_id, variant_id, quantity, unit_price_cents,
  cost_price_cents, discount_cents}`.
  """
  def paid_order(org, %DateTime{} = paid_at, lines, attrs \\ %{}) do
    order_id = uuid()

    paid_on =
      Map.get(attrs, :paid_on) || Palee.TimeZones.ZonedTime.local_date(paid_at, "Europe/Athens")

    lines =
      Enum.map(lines, fn line ->
        discount = Map.get(line, :discount_cents, 0)

        Map.merge(line, %{
          id: uuid(),
          discount_cents: discount,
          total_cents: line.quantity * line.unit_price_cents - discount
        })
      end)

    total = Enum.reduce(lines, 0, &(&2 + &1.total_cents))
    invoice_id = if Map.get(attrs, :finance, true), do: uuid()

    insert!("shop_orders", %{
      id: dump(order_id),
      organization_id: dump(org),
      number: System.unique_integer([:positive]),
      channel: Map.get(attrs, :channel, "pos"),
      status: "picked_up",
      payment_status: "paid",
      payment_mode: "cash",
      currency: "EUR",
      subtotal_cents: total + Enum.reduce(lines, 0, &(&2 + &1.discount_cents)),
      discount_cents: Enum.reduce(lines, 0, &(&2 + &1.discount_cents)),
      total_cents: total,
      paid_cents: total,
      source: Map.get(attrs, :source, "direct"),
      source_ref_id: dump(Map.get(attrs, :source_ref_id)),
      promotion_code: Map.get(attrs, :promotion_code),
      pickup_location_id: dump(Map.get(attrs, :location_id)),
      user_id: dump(Map.get(attrs, :user_id)),
      finance_invoice_id: dump(invoice_id),
      idempotency_key: uuid(),
      placed_at: DateTime.to_naive(paid_at),
      paid_at: DateTime.to_naive(paid_at),
      inserted_at: now(),
      updated_at: now()
    })

    Enum.each(lines, fn line ->
      insert!("shop_order_lines", %{
        id: dump(line.id),
        organization_id: dump(org),
        order_id: dump(order_id),
        product_id: dump(line.product_id),
        variant_id: dump(line.variant_id),
        product_title: Map.get(line, :product_title, "Shaker"),
        variant_title: Map.get(line, :variant_title, "Black"),
        quantity: line.quantity,
        unit_price_cents: line.unit_price_cents,
        cost_price_cents: Map.get(line, :cost_price_cents),
        discount_cents: line.discount_cents,
        total_cents: line.total_cents,
        location_id: dump(Map.get(attrs, :location_id)),
        inserted_at: now(),
        updated_at: now()
      })
    end)

    payment_id =
      if invoice_id do
        finance_rows(org, order_id, invoice_id, lines, total, paid_on, attrs)
      end

    %{
      order_id: order_id,
      invoice_id: invoice_id,
      payment_id: payment_id,
      lines: lines,
      total: total
    }
  end

  defp finance_rows(org, order_id, invoice_id, lines, total, paid_on, attrs) do
    insert!("finance_invoices", %{
      id: dump(invoice_id),
      organization_id: dump(org),
      invoice_number: "SHOP-#{System.unique_integer([:positive])}",
      invoice_type: "manual",
      status: "paid",
      issue_date: paid_on,
      subtotal_cents: total,
      total_cents: total,
      currency: "EUR",
      revenue_stream: "shop",
      inserted_at: now(),
      updated_at: now()
    })

    Enum.each(lines, fn line ->
      insert!("finance_invoice_lines", %{
        id: dump(uuid()),
        organization_id: dump(org),
        finance_invoice_id: dump(invoice_id),
        line_type: "shop_item",
        charge_category: "product",
        description: "Shaker",
        quantity: line.quantity,
        unit_amount_cents: line.unit_price_cents,
        discount_cents: line.discount_cents,
        total_cents: line.total_cents + Map.get(attrs, :line_skew_cents, 0),
        revenue_stream: "shop",
        source_type: "shop_order_line",
        source_id: dump(line.id),
        inserted_at: now(),
        updated_at: now()
      })
    end)

    payment_id = uuid()

    insert!("membership_payments", %{
      id: dump(payment_id),
      organization_id: dump(org),
      membership_id: dump(Map.get(attrs, :membership_id)),
      finance_invoice_id: dump(invoice_id),
      amount_cents: Map.get(attrs, :payment_cents, total),
      currency: "EUR",
      paid_on: paid_on,
      payment_method: "cash",
      payment_status: "paid",
      revenue_stream: "shop",
      source_type: "shop_order",
      source_id: dump(order_id),
      inserted_at: now(),
      updated_at: now()
    })

    payment_id
  end

  @doc "Refunds `cents` of an order: on the order, its line and as a Finance reversal."
  def refund(org, order, cents, quantity \\ 1) do
    [line | _] = order.lines

    Repo.query!(
      "UPDATE shop_orders SET refunded_cents = refunded_cents + $2, payment_status = 'partially_refunded' WHERE id = $1",
      [dump(order.order_id), cents]
    )

    Repo.query!(
      "UPDATE shop_order_lines SET refunded_cents = refunded_cents + $2, refunded_quantity = refunded_quantity + $3 WHERE id = $1",
      [dump(line.id), cents, quantity]
    )

    if order.payment_id do
      insert!("finance_payment_reversals", %{
        id: dump(uuid()),
        organization_id: dump(org),
        membership_payment_id: dump(order.payment_id),
        finance_invoice_id: dump(order.invoice_id),
        reversal_type: "refund",
        amount_cents: cents,
        currency: "EUR",
        occurred_on: Date.utc_today(),
        occurred_at: now(),
        idempotency_key: uuid(),
        inserted_at: now(),
        updated_at: now()
      })
    end
  end

  def pricing_target(org, category, bp) do
    insert!("shop_pricing_targets", %{
      id: dump(uuid()),
      organization_id: dump(org),
      category: category,
      target_margin_bp: bp,
      inserted_at: now(),
      updated_at: now()
    })
  end

  defp insert!(table, row) do
    {1, _} = Repo.insert_all(table, [row])
    :ok
  end
end
