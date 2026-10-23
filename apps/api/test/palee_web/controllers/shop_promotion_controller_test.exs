defmodule PaleeWeb.ShopPromotionControllerTest do
  @moduledoc "ADR-190 «Προώθηση»: a product post with its live card, a product-scoped code, and order attribution."

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)
    other = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(other, :member)

    %{
      owner_conn: put_bearer_token(conn, owner),
      coach_conn: put_bearer_token(conn, coach),
      member_conn: put_bearer_token(conn, member),
      other_conn: put_bearer_token(conn, other),
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

  defp product(ctx, title, price, publish? \\ true) do
    %{"product" => %{"id" => id, "variants" => [variant]}} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.staff}/products", %{
        title: title,
        variants: [%{price_cents: price, initial_quantity: 5}]
      })
      |> json_response(201)

    if publish? do
      ctx.owner_conn
      |> send_json(:put, "#{ctx.staff}/products/#{id}/status", %{status: "published"})
      |> json_response(200)
    end

    {id, variant["id"]}
  end

  test "a promoted product shows its live card in the feed, and its code is attributed and capped",
       ctx do
    {product_id, variant_id} = product(ctx, "Chalk", 2_500)

    %{"post" => post, "promotion_code" => code} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.staff}/products/#{product_id}/promote", %{
        body: "Νέα μαγνησία!",
        promotion_code: %{code: "chalk10", discount_percent: 10, max_redemptions: 1}
      })
      |> json_response(201)

    post_id = post["id"]

    assert %{"code" => "CHALK10", "status" => "active", "redemptions" => 0, "post_id" => ^post_id} =
             code

    assert %{
             "attachment_type" => "product",
             "attachment_id" => ^product_id,
             "audience" => "club_channel"
           } =
             post

    assert post["channel"]["kind"] == "announcements"

    assert %{
             "status" => "available",
             "price_cents" => 2_500,
             "promotion" => %{"code" => "CHALK10", "discount_percent" => 10},
             "promotion_price_cents" => 2_250,
             "buy_link" => %{"params" => link}
           } = post["product"]

    assert link == %{
             "source" => "club_post",
             "source_ref_id" => post_id,
             "promotion_code" => "CHALK10"
           }

    # Members read the card in their feed.
    assert %{"posts" => posts} = ctx.member_conn |> get_json("/api/me/feed") |> json_response(200)
    assert %{"product" => %{"status" => "available"}} = Enum.find(posts, &(&1["id"] == post_id))

    # The basket prices the code; the order from the buy link records the post.
    assert %{
             "total_cents" => 2_250,
             "promotion_code" => %{"code" => "CHALK10", "applied" => true}
           } =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/cart/preview", %{
               lines: [%{variant_id: variant_id, quantity: 1}],
               promotion_code: "chalk10"
             })
             |> json_response(200)

    order_body =
      Map.merge(link, %{
        "lines" => [%{variant_id: variant_id, quantity: 1}],
        "idempotency_key" => key()
      })

    assert %{"order" => %{"id" => order_id} = order} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/orders", order_body)
             |> json_response(201)

    assert %{
             "total_cents" => 2_250,
             "discount_cents" => 250,
             "source" => "club_post",
             "source_ref_id" => ^post_id,
             "promotion_code" => "CHALK10"
           } = order

    # The cap holds: one redemption.
    assert %{"code" => "promotion_code_exhausted"} =
             ctx.other_conn
             |> send_json(:post, "#{ctx.me}/orders", %{order_body | "idempotency_key" => key()})
             |> json_response(409)

    assert %{"promotion_codes" => [%{"redemptions" => 1, "status" => "exhausted"}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/promotion-codes?product_id=#{product_id}")
             |> json_response(200)

    # A cancelled order gives its redemption back.
    ctx.member_conn
    |> send_json(:post, "#{ctx.me}/orders/#{order_id}/cancel", %{})
    |> json_response(200)

    assert %{"promotion_codes" => [%{"id" => code_id, "redemptions" => 0, "status" => "active"}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/promotion-codes?product_id=#{product_id}")
             |> json_response(200)

    # Switched off, the code no longer prices and leaves the card.
    assert %{"promotion_code" => %{"status" => "inactive"}} =
             ctx.owner_conn
             |> send_json(:patch, "#{ctx.staff}/promotion-codes/#{code_id}", %{active: false})
             |> json_response(200)

    assert %{"code" => "promotion_code_invalid"} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/cart/preview", %{
               lines: [%{variant_id: variant_id, quantity: 1}],
               promotion_code: "CHALK10"
             })
             |> json_response(422)

    assert %{"posts" => posts} = ctx.member_conn |> get_json("/api/me/feed") |> json_response(200)

    assert %{"product" => %{"promotion" => nil, "buy_link" => %{"params" => params}}} =
             Enum.find(posts, &(&1["id"] == post_id))

    refute Map.has_key?(params, "promotion_code")
  end

  test "a code is for its product only, and never stacks: the larger discount wins", ctx do
    {chalk, _chalk_variant} = product(ctx, "Chalk", 2_500)
    {_tape, tape_variant} = product(ctx, "Tape", 1_000)

    %{"promotion_code" => _code} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.staff}/products/#{chalk}/promote", %{
        target: "feed",
        promotion_code: %{code: "CHALK-5", discount_cents: 500}
      })
      |> json_response(201)

    assert %{"code" => "promotion_code_not_applicable"} =
             ctx.member_conn
             |> send_json(:post, "#{ctx.me}/cart/preview", %{
               lines: [%{variant_id: tape_variant, quantity: 1}],
               promotion_code: "chalk-5"
             })
             |> json_response(422)
  end

  test "the public feed target, the rules on what can be promoted, and who may", ctx do
    {published, _} = product(ctx, "Shaker", 800)
    {draft, _} = product(ctx, "Belt", 4_000, false)

    assert %{"post" => %{"audience" => "public"}, "promotion_code" => nil} =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.staff}/products/#{published}/promote", %{target: "feed"})
             |> json_response(201)

    assert %{"code" => "product_not_promotable"} =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.staff}/products/#{draft}/promote", %{})
             |> json_response(409)

    assert %{"code" => "invalid_promotion_target"} =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.staff}/products/#{published}/promote", %{
               target: "channel",
               channel_id: Ecto.UUID.generate()
             })
             |> json_response(422)

    assert ctx.coach_conn
           |> send_json(:post, "#{ctx.staff}/products/#{published}/promote", %{})
           |> json_response(403)
  end
end
