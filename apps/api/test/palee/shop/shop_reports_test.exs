defmodule Palee.Shop.ShopReportsTest do
  @moduledoc "ADR-192: shop reports, pricing, reconciliation and finance streams against stored rows."
  use Palee.DataCase

  alias Palee.Application.{ReconcileShopRevenue, ShopReports}
  alias Palee.{Finance, Organizations, Repo}
  alias Palee.Shop.ShopReportStore
  alias Palee.TestFixtures
  alias Palee.TestSupport.ShopReportFixtures, as: F

  # Athens is UTC+2 in December: 22:30 UTC on the 14th is 00:30 on the 15th.
  @now ~U[2026-12-20 10:00:00Z]

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Shop #{System.unique_integer([:positive])}"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    Repo.query!("SELECT set_config('app.organization_id', $1, false)", [organization.id])
    Repo.query!("SELECT set_config('app.user_id', $1, false)", [owner.id])

    product = F.product(organization.id, %{title: "Shaker", category: "gear"})

    variant =
      F.variant(organization.id, product, %{
        price_cents: 1_500,
        cost_price_cents: 600,
        low_stock_threshold: 3,
        inserted_at: ~N[2026-11-01 00:00:00]
      })

    %{context: context, org: organization.id, owner: owner, product: product, variant: variant}
  end

  defp line(%{product: product, variant: variant}, attrs \\ %{}) do
    Map.merge(
      %{
        product_id: product,
        variant_id: variant,
        quantity: 1,
        unit_price_cents: 1_500,
        cost_price_cents: 600
      },
      attrs
    )
  end

  defp window(from, to) do
    %{
      from_at: Palee.TimeZones.ZonedTime.start_of_day(from, "Europe/Athens"),
      to_at: Palee.TimeZones.ZonedTime.start_of_day(Date.add(to, 1), "Europe/Athens"),
      zone: "Europe/Athens",
      location_ids: nil
    }
  end

  describe "sales" do
    test "buckets by the gym's day, nets refunds and ignores unpaid orders", ctx do
      late = F.paid_order(ctx.org, ~U[2026-12-14 22:30:00Z], [line(ctx, %{quantity: 2})])
      F.paid_order(ctx.org, ~U[2026-12-15 09:00:00Z], [line(ctx)])
      F.refund(ctx.org, late, 1_500)

      assert {:ok, report} =
               ShopReports.sales(
                 ctx.context,
                 %{"from" => "2026-12-14", "to" => "2026-12-15"},
                 @now
               )

      assert [%{day: ~D[2026-12-14], orders: 0}, %{day: ~D[2026-12-15]} = day] = report.series
      assert day.orders == 2
      assert day.gross_cents == 4_500
      assert day.refunded_cents == 1_500
      assert day.net_cents == 3_000
      assert day.average_order_value_cents == 1_500
      assert report.window.time_zone == "Europe/Athens"
    end

    test "products, margin, channels and attribution", ctx do
      other = F.product(ctx.org, %{title: "Bar", category: "food"})
      bar = F.variant(ctx.org, other, %{price_cents: 300})
      campaign_code = "WINTER#{System.unique_integer([:positive])}"

      F.paid_order(ctx.org, ~U[2026-12-15 09:00:00Z], [line(ctx, %{quantity: 3})], %{
        channel: "online",
        promotion_code: campaign_code,
        user_id: ctx.owner.id
      })

      F.paid_order(
        ctx.org,
        ~U[2026-12-15 10:00:00Z],
        [
          %{
            product_id: other,
            variant_id: bar,
            quantity: 2,
            unit_price_cents: 300,
            product_title: "Bar"
          }
        ],
        %{source: "club_post", source_ref_id: F.uuid()}
      )

      params = %{"from" => "2026-12-15", "to" => "2026-12-15"}

      {:ok, products} = ShopReports.products(ctx.context, params, @now)

      assert [%{product_name: "Shaker", net_revenue_cents: 4_500, net_units: 3} | _] =
               products.products_by_revenue

      {:ok, margin} = ShopReports.margin(ctx.context, params, @now)
      assert margin.totals.costed_revenue_cents == 4_500
      assert margin.totals.cost_cents == 1_800
      assert margin.totals.margin_cents == 2_700
      assert margin.totals.uncosted_revenue_cents == 600

      {:ok, channels} = ShopReports.channels(ctx.context, params, @now)
      assert Enum.map(channels.by_channel, & &1.channel) == ["online", "pos"]

      {:ok, attribution} = ShopReports.attribution(ctx.context, params, @now)
      assert [%{source: "club_post", net_cents: 600}] = attribution.by_source
      assert [%{promotion_code: code, net_cents: 4_500}] = attribution.by_promotion_code
      assert code == String.upcase(campaign_code)
      assert attribution.attributed.net_cents == 5_100
      assert attribution.unattributed.net_cents == 0
    end

    test "rejects a window over 366 days and needs the analytics capability", ctx do
      assert {:error, :invalid_report_window} =
               ShopReports.sales(
                 ctx.context,
                 %{"from" => "2025-01-01", "to" => "2026-12-01"},
                 @now
               )

      assert {:error, :forbidden} =
               ShopReports.sales(
                 Map.put(ctx.context, :capabilities, %{check_in: :all}),
                 %{},
                 @now
               )
    end
  end

  describe "branch filter" do
    test "orders follow their own branch", ctx do
      a = F.uuid()
      b = F.uuid()
      F.paid_order(ctx.org, ~U[2026-12-15 09:00:00Z], [line(ctx)], %{location_id: a})

      F.paid_order(ctx.org, ~U[2026-12-15 09:00:00Z], [line(ctx, %{quantity: 2})], %{
        location_id: b
      })

      filters = %{window(~D[2026-12-15], ~D[2026-12-15]) | location_ids: [a]}

      assert [%{orders: 1, gross_cents: 1_500}] =
               ShopReportStore.sales_by_day(ctx.context, filters)
    end
  end

  describe "inventory and pricing" do
    test "stock value, low stock and sell-through", ctx do
      location = F.uuid()
      F.stock(ctx.org, ctx.variant, location, 2)
      F.movement(ctx.org, ctx.variant, location, "sale", -6, ~U[2026-12-15 09:00:00Z])

      {:ok, report} =
        ShopReports.inventory(ctx.context, %{"from" => "2026-12-01", "to" => "2026-12-20"}, @now)

      assert report.totals.stock_value_cents == 1_200
      assert [%{low_stock: true, sold_units: 6, sell_through_percent: 75.0}] = report.low_stock
    end

    test "the price ledger records every price change and drives the indicators", ctx do
      %{rows: [[count]]} =
        Repo.query!("SELECT count(*) FROM shop_variant_price_changes WHERE variant_id = $1", [
          Ecto.UUID.dump!(ctx.variant)
        ])

      assert count == 1

      F.paid_order(ctx.org, ~U[2026-12-02 09:00:00Z], [line(ctx, %{quantity: 4})])
      F.set_price(ctx.variant, 1_800)
      F.paid_order(ctx.org, ~U[2026-12-15 09:00:00Z], [line(ctx, %{unit_price_cents: 1_800})])
      F.pricing_target(ctx.org, "gear", 5_000)
      F.backdate_prices(ctx.variant, [~N[2026-11-01 00:00:00], ~N[2026-12-10 00:00:00]])

      assert_raise Postgrex.Error, fn ->
        Repo.query!("DELETE FROM shop_variant_price_changes WHERE variant_id = $1", [
          Ecto.UUID.dump!(ctx.variant)
        ])
      end

      {:ok, pricing} =
        ShopReports.pricing(ctx.context, %{"from" => "2026-12-01", "to" => "2026-12-20"}, @now)

      [row] = pricing.variants
      assert row.price_cents == 1_800
      assert row.margin_percent == 66.7
      assert row.markup_percent == 200.0
      assert row.units_sold == 5
      assert row.elasticity.price_points == 2
      assert [%{from_price_cents: 1_500, to_price_cents: 1_800}] = row.price_changes
      assert row.suggested_price.advisory
      assert row.suggested_price.cost_plus_cents == 1_200
      assert row.suggested_price.inputs.target_margin_source == :category_setting
    end

    test "pricing targets round-trip in exact basis points", ctx do
      assert {:ok, %{targets: targets}} =
               ShopReports.put_pricing_target(ctx.context, %{
                 "category" => "gear",
                 "target_margin_percent" => "37.5"
               })

      assert %{category: "gear", target_margin_bp: 3_750} =
               Enum.find(targets, &(&1.category == "gear"))

      assert {:error, :invalid_pricing_target} =
               ShopReports.put_pricing_target(ctx.context, %{"target_margin_percent" => "37.555"})

      assert {:error, :invalid_pricing_target} =
               ShopReports.put_pricing_target(ctx.context, %{"target_margin_bp" => 9_600})
    end
  end

  describe "reconciliation" do
    test "agreeing rows reconcile per gym day; a skewed line or payment drifts", ctx do
      good = F.paid_order(ctx.org, ~U[2026-12-14 22:30:00Z], [line(ctx, %{quantity: 2})])
      F.refund(ctx.org, good, 1_500)

      assert {:ok, %{ok: true, days: [%{day: ~D[2026-12-15], orders_cents: 1_500} = day]}} =
               ReconcileShopRevenue.call(ctx.context, ~D[2026-12-14], ~D[2026-12-15], emit: false)

      assert day.invoice_lines_cents == 1_500
      assert day.payments_cents == 1_500

      F.paid_order(ctx.org, ~U[2026-12-16 09:00:00Z], [line(ctx)], %{payment_cents: 1_400})
      F.paid_order(ctx.org, ~U[2026-12-17 09:00:00Z], [line(ctx)], %{line_skew_cents: 1})
      F.paid_order(ctx.org, ~U[2026-12-18 09:00:00Z], [line(ctx)], %{finance: false})

      {:ok, result} =
        ReconcileShopRevenue.call(ctx.context, ~D[2026-12-14], ~D[2026-12-18], emit: false)

      refute result.ok

      assert [
               %{day: ~D[2026-12-16], drift_cents: 100, lines_vs_payments_cents: 100},
               %{day: ~D[2026-12-17], drift_cents: 1, orders_vs_lines_cents: -1},
               %{day: ~D[2026-12-18], drift_cents: 1_500, invoice_lines_cents: 0}
             ] = result.drifted

      assert result.drift_cents == 1_601
    end

    test "drift emits telemetry and a warning", ctx do
      F.paid_order(ctx.org, ~U[2026-12-16 09:00:00Z], [line(ctx)], %{payment_cents: 1_000})
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {__MODULE__, ref},
        [:palee, :shop, :reconciliation, :checked],
        fn _event, measurements, metadata, _ -> send(parent, {ref, measurements, metadata}) end,
        nil
      )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          ReconcileShopRevenue.call(ctx.context, ~D[2026-12-16], ~D[2026-12-16])
        end)

      :telemetry.detach({__MODULE__, ref})
      assert_received {^ref, %{drifted_days: 1, drift_cents: 500}, %{result: "drift"}}
      assert log =~ "shop_revenue_drift"
    end
  end

  describe "with the ADR-190 writers" do
    test "a desk sale and a partial refund reconcile and show in every view", ctx do
      alias Palee.Application.Shop.{Checkout, Fulfilment, ManageCatalog}

      {:ok, product} =
        ManageCatalog.create(ctx.context, %{
          title: "Chalk",
          category: "gear",
          variants: [%{price_cents: 800, cost_price_cents: 300, initial_quantity: 10}]
        })

      {:ok, _published} = ManageCatalog.set_status(ctx.context, product.id, :published)
      [variant] = product.variants

      {:ok, order, :created} =
        Checkout.desk_sale(ctx.context, %{
          lines: [%{variant_id: variant.id, quantity: 3}],
          payment_method: "cash",
          idempotency_key: "desk-#{System.unique_integer([:positive])}"
        })

      [order_line] = order.lines

      {:ok, _refund} =
        Fulfilment.refund(ctx.context, order.id, %{
          lines: [%{order_line_id: order_line.id, quantity: 1, restock: true}],
          reason: "Damaged",
          idempotency_key: "refund-#{System.unique_integer([:positive])}"
        })

      now = DateTime.utc_now()
      today = Palee.TimeZones.ZonedTime.local_date(now, "Europe/Athens")

      assert {:ok, %{ok: true, days: [day]}} =
               ReconcileShopRevenue.call(ctx.context, today, today, emit: false)

      assert day.orders_cents == 1_600
      assert day.invoice_lines_cents == 1_600
      assert day.payments_cents == 1_600

      {:ok, sales} = ShopReports.sales(ctx.context, %{"days" => "1"}, now)
      assert sales.totals.net_cents == 1_600
      assert sales.totals.refunded_cents == 800

      {:ok, margin} = ShopReports.margin(ctx.context, %{"days" => "1"}, now)
      assert margin.totals.cost_cents == 600
      assert margin.totals.margin_cents == 1_000

      totals = Finance.financial_summary(ctx.context, %{}).totals
      assert totals.revenue_by_stream["shop"] == 1_600
      assert Enum.sum(Map.values(totals.revenue_by_stream)) == totals.paid_revenue_cents
    end
  end

  describe "accounting export lineage" do
    test "walk-in shop payments and their refunds are exported with stream and source", ctx do
      order = F.paid_order(ctx.org, ~U[2026-12-15 09:00:00Z], [line(ctx)])
      F.refund(ctx.org, order, 500)

      rows = Finance.accounting_export_rows(ctx.context, ~D[2026-12-15], ~D[2026-12-15])

      assert [payment] = rows["payments"]
      assert payment["member_user_id"] == nil
      assert payment["revenue_stream"] == "shop"
      assert payment["report_stream"] == "shop"
      assert payment["source_type"] == "shop_order"
      assert payment["source_id"] == order.order_id
      assert payment["net_amount_cents"] == 1_000

      csv = Palee.Finance.Domain.AccountingExport.csv("payments", rows["payments"])
      assert csv =~ ",shop,shop,shop_order,#{order.order_id}\r\n"

      rows = Finance.accounting_export_rows(ctx.context, Date.utc_today(), Date.utc_today())
      assert [reversal] = rows["reversals"]
      assert reversal["revenue_stream"] == "shop"
      assert reversal["report_stream"] == "shop"
      assert reversal["source_id"] == order.order_id
    end
  end

  describe "finance revenue by stream" do
    test "shop is its own stream, the breakdown adds up and refunds net within it", ctx do
      user = TestFixtures.user_fixture(%{role: :member})

      {:ok, pack} =
        Finance.create_package(ctx.context, %{name: "Ten visits", package_type: "class_pack"})

      {:ok, membership} =
        Finance.upsert_membership(ctx.context, user.id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })

      before = Finance.financial_summary(ctx.context, %{}).totals

      {:ok, subscription} =
        Finance.assign_package(ctx.context, membership.id, pack.id, %{starts_on: Date.utc_today()})

      {:ok, _payment} =
        Finance.record_payment(ctx.context, membership.id, %{
          amount_cents: 9_000,
          payment_method: "cash",
          payment_status: "paid",
          membership_package_subscription_id: subscription.id
        })

      {:ok, _plain} =
        Finance.record_payment(ctx.context, membership.id, %{
          amount_cents: 2_000,
          payment_method: "cash",
          payment_status: "paid"
        })

      today_utc = DateTime.utc_now()

      order =
        F.paid_order(ctx.org, today_utc, [line(ctx, %{quantity: 2})], %{paid_on: Date.utc_today()})

      F.refund(ctx.org, order, 500)

      summary = Finance.financial_summary(ctx.context, %{})
      streams = summary.totals.revenue_by_stream

      assert before.paid_revenue_cents == 0
      assert summary.totals.paid_revenue_cents == 9_000 + 2_000 + 2_500
      assert Enum.sum(Map.values(streams)) == summary.totals.paid_revenue_cents
      assert streams["package"] == 9_000
      assert streams["other"] == 2_000
      assert streams["shop"] == 2_500

      shop = Enum.find(summary.revenue_streams, &(&1.stream == "shop"))
      assert %{gross_cents: 3_000, refunded_cents: 500, net_cents: 2_500, payment_count: 1} = shop

      month =
        Enum.find(
          summary.monthly_revenue_by_stream,
          &(&1.period_start == Date.beginning_of_month(Date.utc_today()))
        )

      assert month.revenue_by_stream["shop"] == 2_500
    end
  end
end
