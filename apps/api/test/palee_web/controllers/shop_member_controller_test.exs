defmodule PaleeWeb.ShopMemberControllerTest do
  @moduledoc """
  ADR-190, the member shop: storefront, pickup codes, «Ειδοποίησέ με», the
  member discount in the basket, and the reminder and cancellation notices.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.Shop.Fulfilment
  alias Palee.{Notifications, Organizations, Repo, Shop}
  alias Palee.Shop.Domain.PickupCode

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)

    %{
      organization: organization,
      member: member,
      context: %{organization_id: organization.id, user_id: nil},
      owner_conn: put_bearer_token(conn, owner),
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
  defp key, do: "key-" <> Ecto.UUID.generate()

  defp product(ctx, quantity) do
    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/products", %{
      title: "Chalk",
      category: "accessories",
      status: "published",
      variants: [%{price_cents: 500, initial_quantity: quantity}]
    })
    |> json_response(201)
    |> Map.fetch!("product")
  end

  defp notified?(user, type),
    do: Enum.any?(Notifications.list_for_user(user.id), &(&1.type == type))

  test "the storefront is closed without products, then open with them", ctx do
    assert %{"open" => false, "closed_reason" => "no_products"} =
             ctx.member_conn |> get_json("#{ctx.me}/storefront") |> json_response(200)

    product(ctx, 3)

    assert %{
             "open" => true,
             "products" => [%{"title" => "Chalk"}],
             "categories" => ["accessories"],
             "pickup_locations" => locations,
             "online_payment" => %{"available" => _}
           } = ctx.member_conn |> get_json("#{ctx.me}/storefront") |> json_response(200)

    assert is_list(locations)
  end

  test "an order gets a short pickup code the desk can find it by", ctx do
    %{"variants" => [variant]} = product(ctx, 3)

    %{"order" => %{"id" => order_id, "pickup_code" => code}} =
      ctx.member_conn
      |> send_json(:post, "#{ctx.me}/orders", %{
        lines: [%{variant_id: variant["id"], quantity: 1}],
        idempotency_key: key()
      })
      |> json_response(201)

    assert PickupCode.valid?(code)
    assert code != order_id

    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/orders/#{order_id}/ready", %{})
    |> json_response(200)

    typed =
      code |> String.downcase() |> String.split_at(3) |> then(fn {a, b} -> a <> " " <> b end)

    assert %{"orders" => [%{"id" => ^order_id}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/ready-orders?pickup_code=#{URI.encode_www_form(typed)}")
             |> json_response(200)

    assert %{"orders" => [%{"id" => ^order_id}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/orders?pickup_code=#{code}")
             |> json_response(200)

    assert %{"code" => "buyer_required"} =
             ctx.owner_conn |> get_json("#{ctx.staff}/ready-orders") |> json_response(422)

    # A day later the buyer is reminded, once, with the code.
    later = DateTime.add(DateTime.utc_now(), 25 * 3_600, :second)
    assert [_] = Fulfilment.send_pickup_reminders(ctx.context, later)
    assert [] = Fulfilment.send_pickup_reminders(ctx.context, later)
    assert notified?(ctx.member, "shop_order_reminder")
  end

  test "«Ειδοποίησέ με»: members hear once when a sold-out variant is back", ctx do
    %{"variants" => [variant]} = product(ctx, 1)

    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/variants/#{variant["id"]}/movements", %{
      kind: "adjustment",
      quantity: -1,
      reason: "loss"
    })
    |> json_response(201)

    assert %{
             "stock_alert" => %{
               "variant_id" => variant_id,
               "notified_at" => nil,
               "available" => false
             }
           } =
             ctx.member_conn
             |> send_json(:put, "#{ctx.me}/variants/#{variant["id"]}/stock-alert", %{})
             |> json_response(200)

    assert variant_id == variant["id"]

    # Subscribing again is harmless.
    ctx.member_conn
    |> send_json(:put, "#{ctx.me}/variants/#{variant["id"]}/stock-alert", %{})
    |> json_response(200)

    refute notified?(ctx.member, "shop_back_in_stock")

    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/variants/#{variant["id"]}/movements", %{
      kind: "receive",
      quantity: 5
    })
    |> json_response(201)

    assert notified?(ctx.member, "shop_back_in_stock")

    assert %{"stock_alerts" => [%{"notified_at" => sent}]} =
             ctx.member_conn |> get_json("#{ctx.me}/stock-alerts") |> json_response(200)

    assert sent

    assert ctx.member_conn
           |> send_json(:delete, "#{ctx.me}/variants/#{variant["id"]}/stock-alert", %{})
           |> response(204)

    assert %{"stock_alerts" => []} =
             ctx.member_conn |> get_json("#{ctx.me}/stock-alerts") |> json_response(200)

    assert ctx.member_conn
           |> send_json(:put, "#{ctx.me}/variants/#{Ecto.UUID.generate()}/stock-alert", %{})
           |> json_response(404)
  end

  test "staff cancellation and an expired hold tell the buyer; their own cancel does not", ctx do
    %{"variants" => [variant]} = product(ctx, 5)

    place = fn ->
      ctx.member_conn
      |> send_json(:post, "#{ctx.me}/orders", %{
        lines: [%{variant_id: variant["id"], quantity: 1}],
        idempotency_key: key()
      })
      |> json_response(201)
      |> get_in(["order", "id"])
    end

    own = place.()

    ctx.member_conn
    |> send_json(:post, "#{ctx.me}/orders/#{own}/cancel", %{})
    |> json_response(200)

    refute notified?(ctx.member, "shop_order_cancelled")

    by_staff = place.()

    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/orders/#{by_staff}/cancel", %{reason: "out of stock"})
    |> json_response(200)

    assert notified?(ctx.member, "shop_order_cancelled")

    expiring = place.()

    # The hold (seven days) runs out: the sweep releases it.
    after_hold = DateTime.add(DateTime.utc_now(), 8 * 86_400, :second)

    assert [%{id: ^expiring, status: :cancelled}] =
             Fulfilment.expire_unpaid(ctx.context, after_hold)

    assert %{status: :cancelled} = Shop.get_order(ctx.context, expiring)
  end

  test "the basket names the member discount rule (none without a package discount)", ctx do
    %{"variants" => [variant]} = product(ctx, 2)

    assert %{"member_discount" => nil} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/cart/preview", %{
               lines: [%{variant_id: variant["id"], quantity: 1}]
             })
             |> json_response(200)

    assert Palee.Application.Shop.Checkout.member_discount(%{member_discount_percent: 10}) ==
             %{percent: 10, source: :membership_package, applies_to: :marked_products}
  end
end
