defmodule PaleeWeb.ShopConsoleControllerTest do
  @moduledoc """
  ADR-190, the staff console's API: catalog and order lists with their
  counts and filters, nested product edits in one transaction, the stock
  ledger across variants, payment methods and product photos.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.{Media, Organizations, Repo}
  alias Palee.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryObjectStore.start()
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    desk = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(desk, :front_desk)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)

    %{
      organization: organization,
      owner_conn: put_bearer_token(conn, owner),
      desk_conn: put_bearer_token(conn, desk),
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

  defp create(ctx, body) do
    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/products", body)
    |> json_response(201)
    |> Map.fetch!("product")
  end

  test "the catalog answers one filter with every filter's counts, searched and by branch", ctx do
    create(ctx, %{
      title: "Chalk",
      category: "accessories",
      status: "published",
      variants: [%{price_cents: 500, initial_quantity: 1, low_stock_threshold: 3}]
    })

    create(ctx, %{
      title: "Tee",
      category: "apparel",
      status: "published",
      variants: [%{price_cents: 2_500, initial_quantity: 40}]
    })

    create(ctx, %{title: "Belt", category: "accessories", variants: [%{price_cents: 4_000}]})

    assert %{"products" => all, "counts" => counts} =
             ctx.owner_conn |> get_json("#{ctx.staff}/products") |> json_response(200)

    assert counts == %{
             "all" => 3,
             "published" => 2,
             "draft" => 1,
             "archived" => 0,
             "low_stock" => 1
           }

    assert length(all) == 3

    assert %{"products" => [%{"title" => "Chalk"}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/products?status=low_stock")
             |> json_response(200)

    assert %{"products" => searched, "counts" => %{"all" => 2}} =
             ctx.owner_conn |> get_json("#{ctx.staff}/products?q=access") |> json_response(200)

    assert searched |> Enum.map(& &1["title"]) |> Enum.sort() == ["Belt", "Chalk"]

    assert %{"products" => [%{"title" => "Belt"}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/products?status=draft")
             |> json_response(200)

    # Products valid at every branch match any branch filter.
    assert %{"counts" => %{"all" => 3}} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/products?location_ids=#{Ecto.UUID.generate()}")
             |> json_response(200)
  end

  test "create with a status, and update the product, its variants and status in one transaction",
       ctx do
    product =
      create(ctx, %{
        title: "Tee",
        status: "published",
        options: [%{name: "Size", values: ["S", "M", "L"]}],
        variants: [
          %{option_values: %{"Size" => "S"}, price_cents: 2_500},
          %{option_values: %{"Size" => "M"}, price_cents: 2_500}
        ]
      })

    assert product["status"] == "published"
    [small, medium] = product["variants"]

    body = %{
      title: "Box tee",
      status: "draft",
      variants: [
        %{id: small["id"], price_cents: 2_200},
        %{option_values: %{"Size" => "L"}, price_cents: 2_700, initial_quantity: 4}
      ]
    }

    assert %{"product" => updated} =
             ctx.owner_conn
             |> send_json(:patch, "#{ctx.staff}/products/#{product["id"]}", body)
             |> json_response(200)

    assert updated["title"] == "Box tee" and updated["status"] == "draft"
    live = Enum.filter(updated["variants"], &is_nil(&1["archived_at"]))
    assert live |> Enum.map(& &1["title"]) |> Enum.sort() == ["L", "S"]
    assert Enum.find(live, &(&1["title"] == "S"))["price_cents"] == 2_200
    assert Enum.find(live, &(&1["title"] == "L"))["stock"]["on_hand"] == 4
    assert Enum.find(updated["variants"], &(&1["id"] == medium["id"]))["archived_at"]

    # Two created + one edited + one added: each price change is one event.
    assert %{rows: [[4]]} =
             Repo.query!(
               "SELECT count(*)::int FROM analytics_events WHERE event_name = 'shop_variant_price_changed'"
             )

    # A bad variant rolls the whole update back.
    assert ctx.owner_conn
           |> send_json(:patch, "#{ctx.staff}/products/#{product["id"]}", %{
             title: "Never saved",
             variants: [%{id: small["id"]}, %{option_values: %{"Size" => "XXL"}, price_cents: 1}]
           })
           |> json_response(422)

    assert %{"product" => %{"title" => "Box tee"}} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/products/#{product["id"]}")
             |> json_response(200)
  end

  test "orders carry the count of every status, a limit and a paid filter", ctx do
    %{"variants" => [variant]} =
      create(ctx, %{
        title: "Bar",
        status: "published",
        variants: [%{price_cents: 300, initial_quantity: 20}]
      })

    for _ <- 1..3 do
      ctx.member_conn
      |> send_json(:post, "#{ctx.me}/orders", %{
        lines: [%{variant_id: variant["id"], quantity: 1}],
        idempotency_key: key()
      })
      |> json_response(201)
    end

    ctx.desk_conn
    |> send_json(:post, "#{ctx.staff}/desk-sales", %{
      lines: [%{variant_id: variant["id"], quantity: 1}],
      payment_method: "cash",
      idempotency_key: key()
    })
    |> json_response(201)

    assert %{
             "orders" => [_],
             "counts" => %{
               "placed" => 3,
               "picked_up" => 1,
               "ready_for_pickup" => 0,
               "cancelled" => 0
             }
           } =
             ctx.desk_conn
             |> get_json("#{ctx.staff}/orders?status=placed&limit=1")
             |> json_response(200)

    assert %{"orders" => [%{"channel" => "pos"}]} =
             ctx.desk_conn |> get_json("#{ctx.staff}/orders?paid=true") |> json_response(200)
  end

  test "the stock ledger across variants filters by kind and pages by cursor", ctx do
    %{"variants" => [a]} =
      create(ctx, %{title: "Chalk", variants: [%{price_cents: 500, initial_quantity: 5}]})

    %{"variants" => [b]} =
      create(ctx, %{title: "Tape", variants: [%{price_cents: 300, initial_quantity: 5}]})

    ctx.owner_conn
    |> send_json(:post, "#{ctx.staff}/variants/#{a["id"]}/movements", %{
      kind: "adjustment",
      quantity: -1,
      reason: "damage"
    })
    |> json_response(201)

    assert %{"movements" => [first], "next_cursor" => cursor} =
             ctx.owner_conn |> get_json("#{ctx.staff}/movements?limit=1") |> json_response(200)

    assert %{"kind" => "adjustment", "product_title" => "Chalk", "quantity" => -1} = first
    assert is_binary(first["actor_name"]) or is_nil(first["actor_name"])

    assert %{"movements" => rest, "next_cursor" => nil} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/movements?limit=50&cursor=#{cursor}")
             |> json_response(200)

    assert length(rest) == 2 and Enum.all?(rest, &(&1["kind"] == "receive"))
    refute Enum.any?(rest, &(&1["id"] == first["id"]))

    assert %{"movements" => [%{"variant_id" => b_id}]} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/movements?kind=receive&product_id=#{b["product_id"]}")
             |> json_response(200)

    assert b_id == b["id"]

    assert %{"code" => "invalid_cursor"} =
             ctx.owner_conn
             |> get_json("#{ctx.staff}/movements?cursor=nope")
             |> json_response(400)
  end

  test "payment methods come from the payment port", ctx do
    config = Application.get_env(:palee, Palee.Infrastructure.Shop.MockPaymentProvider)

    try do
      Application.put_env(:palee, Palee.Infrastructure.Shop.MockPaymentProvider,
        mode: :unavailable
      )

      assert %{"payment_methods" => methods} =
               ctx.desk_conn |> get_json("#{ctx.staff}/payment-methods") |> json_response(200)

      by_id = Map.new(methods, &{&1["id"], &1})
      assert %{"available" => true, "channel" => "pos"} = by_id["cash"]
      assert %{"available" => true} = by_id["card_manual"]

      assert %{"available" => false, "reason" => "no_provider", "channel" => "online"} =
               by_id["card_online"]
    after
      Application.put_env(:palee, Palee.Infrastructure.Shop.MockPaymentProvider, config)
    end
  end

  test "product photos upload as shop_product_photo and show with their URLs", ctx do
    body = jpeg(800, 600)

    assert ctx.desk_conn
           |> send_json(:post, "#{ctx.staff}/photos", %{
             content_type: "image/jpeg",
             byte_size: byte_size(body)
           })
           |> json_response(403)

    assert %{"media_id" => media_id, "upload_url" => _} =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.staff}/photos", %{
               content_type: "image/jpeg",
               byte_size: byte_size(body)
             })
             |> json_response(200)

    media = Media.get(%{organization_id: ctx.organization.id}, :tenant, media_id)
    :ok = MemoryObjectStore.put_object(:media_public, media.object_key, body, "image/jpeg")

    assert %{"media" => %{"status" => "ready"}} =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.staff}/photos/#{media_id}/complete", %{})
             |> json_response(200)

    product =
      create(ctx, %{
        title: "Shaker",
        status: "published",
        media_ids: [media_id],
        variants: [%{price_cents: 800}]
      })

    assert [%{"id" => ^media_id, "url" => url, "thumb_url" => url, "width" => 800}] =
             product["media"]

    assert url =~ "https://media.test/media_public/"

    # Saved with a product, the photo is attached (the orphan sweep keeps it).
    assert Media.get(%{organization_id: ctx.organization.id}, :tenant, media_id).attached_at

    assert %{"products" => [%{"media" => [%{"id" => ^media_id}]}]} =
             ctx.member_conn |> get_json("#{ctx.me}/products") |> json_response(200)
  end
end
