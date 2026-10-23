defmodule Palee.Shop.Domain.OrderRulesTest do
  use ExUnit.Case, async: true

  alias Palee.Shop.Domain.{
    OrderLifecycle,
    OrderPricing,
    ProductPolicy,
    RevenueLineage,
    StockStatus
  }

  defp product(attrs \\ %{}) do
    Map.merge(
      %{
        id: "p1",
        title: "Tee",
        status: :published,
        sell_in_app: true,
        sell_at_desk: true,
        visibility: :members_only,
        member_discount_applies: false,
        per_person_limit: nil
      },
      attrs
    )
  end

  defp variant(attrs \\ %{}) do
    Map.merge(
      %{
        id: "v1",
        title: "M",
        sku: "TEE-M",
        price_cents: 2_500,
        cost_price_cents: 900,
        tax_class: "standard",
        currency: "EUR",
        archived_at: nil
      },
      attrs
    )
  end

  describe "OrderLifecycle" do
    test "pay at pickup: ready while unpaid, handed over only when paid" do
      order = %{
        status: :placed,
        payment_status: :pending_payment,
        paid_cents: 0,
        refunded_cents: 0
      }

      assert {:ok, %{status: :ready_for_pickup}} =
               OrderLifecycle.transition(order, :mark_ready, %{})

      ready = %{order | status: :ready_for_pickup}
      assert {:error, :order_not_paid} = OrderLifecycle.transition(ready, :pick_up, %{})

      assert {:ok, %{payment_status: :paid}} =
               OrderLifecycle.transition(ready, :pay, %{amount_cents: 10})

      assert {:ok, %{status: :picked_up}} =
               OrderLifecycle.transition(%{ready | payment_status: :paid}, :pick_up, %{})
    end

    test "a paid order is refunded, not cancelled; refunds never exceed what was paid" do
      paid = %{
        status: :ready_for_pickup,
        payment_status: :paid,
        paid_cents: 5_000,
        refunded_cents: 0
      }

      assert {:error, :order_paid_refund_first} = OrderLifecycle.transition(paid, :cancel, %{})

      assert {:ok, %{payment_status: :partially_refunded, refunded_cents: 2_000}} =
               OrderLifecycle.transition(paid, :refund, %{amount_cents: 2_000})

      assert {:error, :refund_exceeds_paid} =
               OrderLifecycle.transition(%{paid | refunded_cents: 4_000}, :refund, %{
                 amount_cents: 2_000
               })

      assert {:ok, %{payment_status: :refunded}} =
               OrderLifecycle.transition(%{paid | refunded_cents: 3_000}, :refund, %{
                 amount_cents: 2_000
               })
    end

    test "one state vocabulary folds both axes" do
      assert OrderLifecycle.state(%{status: :placed, payment_status: :pending_payment}) ==
               :pending_payment

      assert OrderLifecycle.state(%{status: :placed, payment_status: :paid}) == :paid

      assert OrderLifecycle.state(%{status: :ready_for_pickup, payment_status: :pending_payment}) ==
               :ready_for_pickup

      assert OrderLifecycle.state(%{status: :picked_up, payment_status: :partially_refunded}) ==
               :partially_refunded

      assert OrderLifecycle.state(%{status: :cancelled, payment_status: :void}) == :cancelled
    end

    test "online needs a provider and on-account needs a membership" do
      none = %{online_available: false, on_account_allowed: false}
      assert {:error, :online_payment_unavailable} = OrderLifecycle.checkout_mode("online", none)
      assert {:error, :on_account_not_allowed} = OrderLifecycle.checkout_mode("on_account", none)
      assert {:ok, :at_pickup} = OrderLifecycle.checkout_mode("at_pickup", none)

      assert {:ok, :online} =
               OrderLifecycle.checkout_mode(:online, %{none | online_available: true})
    end
  end

  describe "OrderPricing" do
    test "prices from the catalog, merges repeated variants and applies the member discount" do
      catalog = %{
        "v1" => %{variant: variant(), product: product(%{member_discount_applies: true})}
      }

      assert {:ok,
              %{lines: [line], subtotal_cents: 7_500, discount_cents: 750, total_cents: 6_750}} =
               OrderPricing.price(
                 [%{variant_id: "v1", quantity: 2}, %{"variant_id" => "v1", "quantity" => 1}],
                 catalog,
                 channel: :online,
                 member_discount_percent: 10
               )

      assert line.quantity == 3 and line.cost_price_cents == 900 and line.sku == "TEE-M"
    end

    test "refuses drafts, the wrong channel, unknown variants and the per-person limit" do
      draft = %{"v1" => %{variant: variant(), product: product(%{status: :draft})}}
      desk_only = %{"v1" => %{variant: variant(), product: product(%{sell_in_app: false})}}
      limited = %{"v1" => %{variant: variant(), product: product(%{per_person_limit: 2})}}
      items = [%{variant_id: "v1", quantity: 1}]

      assert {:error, :product_not_available} = OrderPricing.price(items, draft, channel: :online)

      assert {:error, :product_not_available} =
               OrderPricing.price(items, desk_only, channel: :online)

      assert {:ok, _} = OrderPricing.price(items, desk_only, channel: :pos)
      assert {:error, :variant_not_found} = OrderPricing.price(items, %{}, channel: :pos)

      assert {:error, :per_person_limit_exceeded} =
               OrderPricing.price(items, limited, channel: :online, already: %{"p1" => 2})
    end
  end

  describe "ProductPolicy" do
    test "options: at most two axes, variants name one value per axis" do
      {:ok, options} =
        ProductPolicy.normalize_options([
          %{name: "Size", values: ["S", "M"]},
          %{"name" => "Colour", "values" => ["Black"]}
        ])

      assert {:ok, %{"Size" => "M", "Colour" => "Black"}} =
               ProductPolicy.validate_option_values(options, %{"Size" => "M", "Colour" => "Black"})

      assert {:error, :invalid_option_values} =
               ProductPolicy.validate_option_values(options, %{
                 "Size" => "XL",
                 "Colour" => "Black"
               })

      assert ProductPolicy.variant_title(options, %{"Size" => "M", "Colour" => "Black"}) ==
               "M / Black"

      assert {:error, :invalid_product_options} =
               ProductPolicy.normalize_options([
                 %{name: "A", values: ["1"]},
                 %{name: "B", values: ["1"]},
                 %{name: "C", values: ["1"]}
               ])
    end

    test "lifecycle and publishing" do
      assert :ok = ProductPolicy.transition(:draft, :published)

      assert {:error, :invalid_product_transition} =
               ProductPolicy.transition(:archived, :published)

      assert {:error, :product_has_no_variants} = ProductPolicy.publishable(product(), [])
      assert ProductPolicy.public?(product(%{visibility: :anyone}))
      refute ProductPolicy.visible_to?(product(), :visitor)
      assert ProductPolicy.visible_to?(product(%{visibility: :anyone}), :visitor)
    end
  end

  describe "RevenueLineage" do
    test "every invoice line and the payment carry the shop stream and their source" do
      order = %{
        id: "o1",
        number: 7,
        membership_id: nil,
        user_id: nil,
        currency: "EUR",
        channel: :pos,
        source: :desk,
        pickup_location_id: nil,
        finance_invoice_id: "inv1",
        total_cents: 2_500
      }

      line = %{
        id: "l1",
        product_id: "p1",
        variant_id: "v1",
        sku: "TEE-M",
        tax_class: "standard",
        cost_price_cents: 900,
        product_title: "Tee",
        variant_title: "M",
        quantity: 1,
        unit_price_cents: 2_500,
        discount_cents: 0,
        total_cents: 2_500
      }

      invoice = RevenueLineage.invoice(order, [line], ~D[2026-10-23])
      assert invoice["revenue_stream"] == "shop"

      assert [
               %{
                 "line_type" => "shop_item",
                 "revenue_stream" => "shop",
                 "source_type" => "shop_order_line",
                 "source_id" => "l1",
                 "params" => %{
                   "variant_id" => "v1",
                   "product_id" => "p1",
                   "shop_order_id" => "o1"
                 }
               }
             ] = invoice["lines"]

      payment = RevenueLineage.payment(order, :card_manual, ~D[2026-10-23], %{})

      assert %{
               "revenue_stream" => "shop",
               "source_type" => "shop_order",
               "source_id" => "o1",
               "payment_method" => "card_manual"
             } = payment
    end

    test "refund allocation: per unit, the last unit takes the rounding remainder" do
      line = %{id: "l1", quantity: 3, refunded_quantity: 0, total_cents: 1_000, refunded_cents: 0}

      assert {:ok, [%{cents: 333}], 333} =
               RevenueLineage.allocate_refund([line], [%{order_line_id: "l1", quantity: 1}])

      after_two = %{line | refunded_quantity: 2, refunded_cents: 666}

      assert {:ok, [%{cents: 334}], 334} =
               RevenueLineage.allocate_refund([after_two], [%{order_line_id: "l1", quantity: 1}])

      assert {:error, :refund_exceeds_quantity} =
               RevenueLineage.allocate_refund([after_two], [%{order_line_id: "l1", quantity: 2}])
    end
  end

  describe "StockStatus" do
    test "threshold and sales rate" do
      now = ~U[2026-10-23 12:00:00Z]
      assert %{status: :out} = StockStatus.assess(0, [], nil, now)
      assert %{status: :low} = StockStatus.assess(3, [], 3, now)
      assert %{status: :ok} = StockStatus.assess(30, [], 3, now)

      sales =
        for day <- 1..20,
            do: %{quantity: -2, occurred_at: DateTime.add(now, -day * 86_400, :second)}

      # 2 a day: 10 units last 5 days (critical), 30 units 15 days (low).
      assert %{status: :critical} = StockStatus.assess(10, sales, nil, now)
      assert %{status: :low} = StockStatus.assess(30, sales, nil, now)
      assert StockStatus.alert?(:ok, :low)
      refute StockStatus.alert?(:low, :ok)
    end
  end
end
