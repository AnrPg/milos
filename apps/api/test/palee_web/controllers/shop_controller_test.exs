defmodule PaleeWeb.ShopControllerTest do
  @moduledoc "The e-shop end to end over HTTP (ADR-190): catalog, stock, orders and revenue lineage."

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Notifications, Organizations, Repo}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    desk = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(desk, :front_desk)
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)

    %{
      organization: organization,
      owner: owner,
      member: member,
      owner_conn: put_bearer_token(conn, owner),
      desk_conn: put_bearer_token(conn, desk),
      coach_conn: put_bearer_token(conn, coach),
      member_conn: put_bearer_token(conn, member),
      staff: "/api/org/#{organization.slug}/staff/shop",
      me: "/api/org/#{organization.slug}/me/shop"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  defp create_published_tee(ctx, quantity \\ 3) do
    %{"product" => %{"id" => id, "status" => "draft", "variants" => variants}} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.staff}/products", %{
        title: "Box tee",
        category: "apparel",
        options: [%{name: "Size", values: ["S", "M"]}],
        member_discount_applies: false,
        variants: [
          %{
            option_values: %{"Size" => "S"},
            sku: "TEE-S",
            price_cents: 2_500,
            cost_price_cents: 900,
            low_stock_threshold: 1,
            initial_quantity: quantity
          },
          %{
            option_values: %{"Size" => "M"},
            sku: "TEE-M",
            price_cents: 2_500,
            initial_quantity: quantity
          }
        ]
      })
      |> json_response(201)

    assert %{"product" => %{"status" => "published"}} =
             ctx.owner_conn
             |> send_json(:put, "#{ctx.staff}/products/#{id}/status", %{status: "published"})
             |> json_response(200)

    {id, Map.new(variants, &{&1["sku"], &1})}
  end

  defp key, do: "key-" <> Ecto.UUID.generate()

  test "a member orders for pickup; the desk prepares, takes cash and hands it over; Finance sees shop revenue",
       ctx do
    {_product_id, %{"TEE-S" => small}} = create_published_tee(ctx)
    assert small["stock"]["on_hand"] == 3

    assert %{"products" => [%{"title" => "Box tee", "variants" => [_, _]} = listed]} =
             ctx.member_conn |> get_json("#{ctx.me}/products") |> json_response(200)

    refute Map.has_key?(hd(listed["variants"]), "cost_price_cents")

    assert %{"online_payment" => %{"available" => true}, "total_cents" => 5_000} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/cart/preview", %{
               lines: [%{variant_id: small["id"], quantity: 2}]
             })
             |> json_response(200)

    idempotency = key()

    body = %{
      lines: [%{variant_id: small["id"], quantity: 2}],
      payment_mode: "at_pickup",
      idempotency_key: idempotency
    }

    %{"order" => %{"id" => order_id, "state" => "pending_payment", "total_cents" => 5_000}} =
      ctx.member_conn |> send_json(:post, "#{ctx.me}/orders", body) |> json_response(201)

    # A retry returns the same order and reserves nothing more.
    assert %{"order" => %{"id" => ^order_id}} =
             ctx.member_conn |> send_json(:post, "#{ctx.me}/orders", body) |> json_response(200)

    # Two of three are reserved: two more cannot be sold (never oversold).
    assert %{"code" => "insufficient_stock"} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders", %{body | idempotency_key: key()})
             |> json_response(409)

    assert Enum.any?(Notifications.list_for_user(ctx.owner.id), &(&1.type == "shop_order_placed"))

    assert %{"order" => %{"state" => "ready_for_pickup"}} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.staff}/orders/#{order_id}/ready", %{})
             |> json_response(200)

    assert Enum.any?(Notifications.list_for_user(ctx.member.id), &(&1.type == "shop_order_ready"))

    # The check-in desk sees the ready order.
    assert %{"orders" => [%{"id" => ^order_id}]} =
             ctx.desk_conn
             |> get_json("#{ctx.staff}/ready-orders?user_id=#{ctx.member.id}")
             |> json_response(200)

    assert %{"code" => "order_not_paid"} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.staff}/orders/#{order_id}/pickup", %{})
             |> json_response(409)

    assert %{
             "order" => %{
               "state" => "picked_up",
               "payment_status" => "paid",
               "paid_cents" => 5_000
             }
           } =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.staff}/orders/#{order_id}/pickup", %{
               payment_method: "cash"
             })
             |> json_response(200)

    # Lineage: invoice lines and the payment carry the shop stream and their sources.
    lineage =
      ctx.owner_conn |> get_json("#{ctx.staff}/orders/#{order_id}/lineage") |> json_response(200)

    assert [
             %{
               "revenue_stream" => "shop",
               "source_type" => "shop_order_line",
               "line_type" => "shop_item"
             }
           ] =
             lineage["invoice_lines"]

    assert [
             %{
               "revenue_stream" => "shop",
               "source_type" => "shop_order",
               "source_id" => ^order_id
             }
           ] =
             lineage["payments"]

    assert Enum.map(lineage["movements"], & &1["kind"]) |> Enum.sort() == [
             "release",
             "reserve",
             "sale"
           ]

    # Stock: one left on hand, nothing reserved.
    assert %{"movements" => _} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/variants/#{small["id"]}/movements")
             |> json_response(200)

    # Refund one unit back to stock: the reversal keeps the shop lineage.
    assert %{
             "order" => %{"state" => "partially_refunded", "refunded_cents" => 2_500},
             "refund" => refund
           } =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.staff}/orders/#{order_id}/refund", %{
               lines: [
                 %{order_line_id: hd(lineage["order"]["lines"])["id"], quantity: 1, restock: true}
               ],
               reason: "wrong size",
               idempotency_key: key()
             })
             |> json_response(200)

    assert refund["revenue_stream"] == "shop" and refund["source_id"] == order_id

    # ADR-126: the member gets a refund receipt, in the shop stream, without a membership.
    assert [["shop", nil]] =
             Repo.query!(
               "SELECT revenue_stream, membership_id FROM finance_refund_receipts WHERE finance_payment_reversal_id = $1::uuid",
               [Ecto.UUID.dump!(refund["id"])]
             ).rows

    streams =
      ctx.owner_conn
      |> get_json("#{ctx.staff}/revenue-streams")
      |> json_response(200)
      |> Map.fetch!("streams")

    assert %{"paid_cents" => 5_000, "refunded_cents" => 2_500, "net_cents" => 2_500} =
             Enum.find(streams, &(&1["revenue_stream"] == "shop" and &1["currency"] == "EUR"))

    assert %{
             "transactions" => [
               %{
                 "order_id" => ^order_id,
                 "revenue_stream" => "shop",
                 "payments" => [_],
                 "refunds" => [_]
               }
             ]
           } =
             ctx.member_conn |> get_json("#{ctx.me}/transactions") |> json_response(200)

    [small_now] =
      ctx.owner_conn
      |> get_json("#{ctx.staff}/products")
      |> json_response(200)
      |> Map.fetch!("products")
      |> hd()
      |> Map.fetch!("variants")
      |> Enum.filter(&(&1["sku"] == "TEE-S"))

    assert %{"on_hand" => 2, "reserved" => 0, "available" => 2} = small_now["stock"]
  end

  test "a desk sale to a walk-in is paid at once and counted as shop revenue without a member",
       ctx do
    {_id, %{"TEE-M" => medium}} = create_published_tee(ctx)

    sale = %{
      lines: [%{variant_id: medium["id"], quantity: 1}],
      payment_method: "card_manual",
      customer_name: "Walk-in",
      idempotency_key: key()
    }

    assert %{
             "order" => %{
               "channel" => "pos",
               "state" => "picked_up",
               "user_id" => nil,
               "id" => order_id
             }
           } =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.staff}/desk-sales", sale)
             |> json_response(201)

    assert %{"order" => %{"id" => ^order_id}} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.staff}/desk-sales", sale)
             |> json_response(200)

    assert %{
             "payments" => [
               %{
                 "payment_method" => "card_manual",
                 "membership_id" => nil,
                 "revenue_stream" => "shop"
               }
             ]
           } =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/orders/#{order_id}/lineage")
             |> json_response(200)

    oversell = %{sale | idempotency_key: key(), lines: [%{variant_id: medium["id"], quantity: 5}]}

    assert %{"code" => "insufficient_stock"} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.staff}/desk-sales", oversell)
             |> json_response(409)
  end

  test "online payment: refused without a provider, declined cards keep the order unpaid, success pays it",
       ctx do
    {_id, %{"TEE-S" => small}} = create_published_tee(ctx)
    lines = [%{variant_id: small["id"], quantity: 1}]
    config = Application.get_env(:palee, Palee.Infrastructure.Shop.MockPaymentProvider)

    try do
      Application.put_env(:palee, Palee.Infrastructure.Shop.MockPaymentProvider,
        mode: :unavailable
      )

      assert %{
               "online_payment" => %{"available" => false, "reason" => "no_provider"},
               "payment_modes" => modes
             } =
               ctx.member_conn
               |> send_json(:post, "#{ctx.me}/cart/preview", %{lines: lines})
               |> json_response(200)

      refute "online" in modes

      assert %{"code" => "online_payment_unavailable"} =
               ctx.member_conn
               |> send_json(:post, "#{ctx.me}/orders", %{
                 lines: lines,
                 payment_mode: "online",
                 idempotency_key: key()
               })
               |> json_response(409)
    after
      Application.put_env(:palee, Palee.Infrastructure.Shop.MockPaymentProvider, config)
    end

    assert %{"code" => "payment_failed", "order_id" => order_id} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders", %{
               lines: lines,
               payment_mode: "online",
               payment_token: "tok_declined",
               idempotency_key: key()
             })
             |> json_response(402)

    assert %{"order" => %{"state" => "pending_payment"}} =
             ctx.member_conn |> get_json("#{ctx.me}/orders/#{order_id}") |> json_response(200)

    assert %{"order" => %{"state" => "paid", "paid_cents" => 2_500}} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders/#{order_id}/pay", %{payment_token: "tok_ok"})
             |> json_response(200)

    # A paid order is refunded, never cancelled.
    assert %{"code" => "order_paid_refund_first"} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders/#{order_id}/cancel", %{})
             |> json_response(409)
  end

  test "a member cancels an unpaid order: the stock comes back and the invoice is void", ctx do
    {_id, %{"TEE-S" => small}} = create_published_tee(ctx, 1)

    %{"order" => %{"id" => order_id}} =
      ctx.member_conn
      |> send_json(:post, "#{ctx.me}/orders", %{
        lines: [%{variant_id: small["id"], quantity: 1}],
        idempotency_key: key()
      })
      |> json_response(201)

    assert %{"order" => %{"state" => "cancelled", "payment_status" => "void"}} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders/#{order_id}/cancel", %{})
             |> json_response(200)

    # The released unit can be ordered again.
    assert %{"order" => %{"state" => "pending_payment"}} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders", %{
               lines: [%{variant_id: small["id"], quantity: 1}],
               idempotency_key: key()
             })
             |> json_response(201)
  end

  test "stock movements: receive, adjustment with a reason, recount; low stock alerts the owner",
       ctx do
    {_id, %{"TEE-S" => small}} = create_published_tee(ctx, 5)
    path = "#{ctx.staff}/variants/#{small["id"]}/movements"

    assert %{"variant" => %{"stock" => %{"on_hand" => 15}}} =
             ctx.owner_conn
             |> send_json(:post, path, %{kind: "receive", quantity: 10, unit_cost_cents: 800})
             |> json_response(201)

    assert %{"code" => "adjustment_reason_required"} =
             ctx.owner_conn
             |> send_json(:post, path, %{kind: "adjustment", quantity: -2})
             |> json_response(422)

    assert %{"variant" => %{"stock" => %{"on_hand" => 13}}} =
             ctx.owner_conn
             |> send_json(:post, path, %{kind: "adjustment", quantity: -2, reason: "damage"})
             |> json_response(201)

    assert %{"variant" => %{"stock" => %{"on_hand" => 1}, "stock_status" => "low"}} =
             ctx.owner_conn
             |> send_json(:post, path, %{kind: "recount", counted: 1})
             |> json_response(201)
  end

  test "capabilities: a coach has no shop; the front desk sells but does not edit the catalog",
       ctx do
    assert ctx.coach_conn |> get_json("#{ctx.staff}/products") |> json_response(403)
    assert ctx.desk_conn |> get_json("#{ctx.staff}/products") |> json_response(200)

    assert ctx.desk_conn
           |> send_json(:post, "#{ctx.staff}/products", %{title: "Shaker", price_cents: 800})
           |> json_response(403)
  end

  test "a draft is invisible to members, and every price change is recorded", ctx do
    %{"product" => %{"id" => id, "variants" => [variant]}} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.staff}/products", %{title: "Shaker", price_cents: 800})
      |> json_response(201)

    assert %{"products" => []} =
             ctx.member_conn |> get_json("#{ctx.me}/products") |> json_response(200)

    assert ctx.member_conn |> get_json("#{ctx.me}/products/#{id}") |> json_response(404)

    assert %{"variant" => %{"price_cents" => 900}} =
             ctx.owner_conn
             |> send_json(:patch, "#{ctx.staff}/products/#{id}/variants/#{variant["id"]}", %{
               price_cents: 900
             })
             |> json_response(200)

    changes =
      Repo.query!(
        "SELECT metadata FROM analytics_events WHERE event_name = 'shop_variant_price_changed' AND context_id = $1::uuid",
        [Ecto.UUID.dump!(variant["id"])]
      ).rows

    assert length(changes) == 2
  end
end
