defmodule PaleeWeb.BoxSearchControllerTest do
  @moduledoc """
  ADR-216: «Βρες» finds a box or an independent coach by name, as the RLS
  runtime role: only live businesses with a published page, accents and
  case ignored, the Latin spelling too, no map point needed, word starts
  first, with the viewer's follow status.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.{Facility, Organizations, Repo}

  setup %{conn: conn} do
    %{as: fn user -> put_bearer_token(conn, user) end, me: user_fixture()}
  end

  defp business(name, opts \\ []) do
    {:ok, organization} = Organizations.create_organization(%{name: name})
    owner = user_fixture()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    if opts[:located] do
      {:ok, _location} =
        Facility.create_location(context, %{
          "name" => name,
          "address" => "Οδός 1",
          "latitude" => 38.01,
          "longitude" => 23.738,
          "neighbourhood" => "Κυψέλη",
          "city" => "Αθήνα"
        })
    end

    if Keyword.get(opts, :publish, true) do
      {:ok, profile} =
        UpdateBoxPublicProfile.call(context, %{
          "about" => "Καλώς ήρθες.",
          "disciplines" => ["crossfit"]
        })

      {:ok, _profile} =
        PublishBoxPublicProfile.publish(context, %{"lock_version" => profile.lock_version})
    end

    # ADR-184: a business still in demo never answers, published or not.
    if opts[:demo] do
      Repo.query!("UPDATE organizations SET activation = 'demo' WHERE id = $1", [
        Ecto.UUID.dump!(organization.id)
      ])
    end

    organization
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp search(ctx, user, q) do
    ctx.as.(user)
    |> get("/api/box-search?q=#{URI.encode_www_form(q)}")
    |> json_response(200)
    |> Map.fetch!("boxes")
  end

  defp ids(boxes), do: Enum.map(boxes, & &1["organization_id"])

  test "finds a live, published business by name; drafts and demos stay hidden", ctx do
    unique = System.unique_integer([:positive])
    live = business("Τολάρας Box #{unique}", located: true)
    unlocated = business("Τολάρας Studio #{unique}")
    draft = business("Τολάρας Draft #{unique}", publish: false)
    demo = business("Τολάρας Demo #{unique}", demo: true)

    found = search(ctx, ctx.me, "Τολάρας")
    assert live.id in ids(found)
    # Γύρω μου needs a map point; the name search does not.
    assert unlocated.id in ids(found)
    refute draft.id in ids(found)
    refute demo.id in ids(found)

    assert %{
             "name" => name,
             "slug" => slug,
             "provider_kind" => "gym",
             "neighbourhood" => "Κυψέλη",
             "city" => "Αθήνα",
             "my_status" => "none"
           } = Enum.find(found, &(&1["organization_id"] == live.id))

    assert name =~ "Τολάρας Box"
    assert slug == live.slug
  end

  test "accents, case and the Latin spelling all find the Greek name", ctx do
    unique = System.unique_integer([:positive])
    box = business("Τολάρας #{unique}")

    for q <- ["τολαρας #{unique}", "ΤΟΛΆΡΑΣ #{unique}", "tolaras #{unique}", "tolaras-#{unique}"] do
      assert box.id in ids(search(ctx, ctx.me, q)), "#{q} should find the box"
    end
  end

  test "names that start with the query come first, then a word that starts with it", ctx do
    unique = System.unique_integer([:positive])
    inside = business("Alphakyma#{unique} Gym")
    word = business("Alpha Kyma#{unique} Box")
    starts = business("Kyma#{unique} Strength")

    assert ids(search(ctx, ctx.me, "kyma#{unique}")) == [starts.id, word.id, inside.id]
  end

  test "forgives a typo from three characters, literal matches first", ctx do
    unique = System.unique_integer([:positive])
    melissa = business("Melissa Strength #{unique}")
    melisa = business("Melisa Yoga #{unique}")

    assert ids(search(ctx, ctx.me, "Melisa Yoga #{unique}")) |> hd() == melisa.id
    assert melissa.id in ids(search(ctx, ctx.me, "Melisa Strength #{unique}"))
    refute melissa.id in ids(search(ctx, ctx.me, "zz"))
  end

  test "shows whether the viewer follows the business", ctx do
    unique = System.unique_integer([:positive])
    box = business("Followed Box #{unique}")

    ctx.as.(ctx.me)
    |> send_json(:post, "/api/me/follows", %{target_type: "organization", target_id: box.id})
    |> json_response(200)

    assert [%{"my_status" => "active"}] = search(ctx, ctx.me, "Followed Box #{unique}")
  end

  test "answers nothing below two characters", ctx do
    assert search(ctx, ctx.me, "a") == []
  end
end
