defmodule Palee.Identity.DemoPeoplePrivacyTest do
  @moduledoc """
  ADR-184 follow-up «Mock people stay private»: the mock people a demo
  business seeds carry a durable mark (`users.demo_organization_id`) and no
  person-discovery path lists them to anyone but that business's staff.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Buddies, Identity, Organizations}

  alias Palee.Application.{
    FindPRGrantee,
    Follows,
    SearchUsers,
    SocialProfile
  }

  setup %{conn: conn} do
    owner = user_fixture()
    outsider = user_fixture()
    as = fn user -> put_bearer_token(conn, user) end

    %{"id" => org_id, "slug" => slug} =
      as.(owner)
      |> post_json("/api/business-accounts", %{
        business_kind: "gym",
        business_name: "Demo Box #{System.unique_integer([:positive])}",
        city: "Αθήνα",
        timezone: "Europe/Athens"
      })
      |> json_response(201)

    as.(owner)
    |> post_json("/api/org/#{slug}/admin/business/demo-data", %{section: "members"})
    |> json_response(200)

    mock_ids = Identity.demo_user_ids(org_id)
    mock = Identity.find_by_id(hd(mock_ids))

    %{
      conn: conn,
      as: as,
      owner: owner,
      outsider: outsider,
      org_id: org_id,
      slug: slug,
      mock_ids: mock_ids,
      mock: mock
    }
  end

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp sql!(sql, params), do: Palee.Repo.query!(sql, params)
  defp uuid(id), do: Ecto.UUID.dump!(id)

  defp handle_prefix(mock), do: mock.handle |> String.split("_demo_") |> hd()

  describe "the durable mark" do
    test "the seeder marks every mock person with its demo business", ctx do
      assert length(ctx.mock_ids) == 8

      for id <- ctx.mock_ids do
        user = Identity.find_by_id(id)
        assert user.demo_organization_id == ctx.org_id
        assert Identity.demo_user?(user)
        assert Identity.demo_user?(id)
      end

      refute Identity.demo_user?(ctx.owner)
      refute Identity.demo_user?(ctx.owner.id)
      refute Identity.demo_user?(nil)
    end

    test "the database refuses to add or remove the mark", ctx do
      for {sql, id} <- [
            {"UPDATE users SET demo_organization_id = NULL WHERE id = $1", ctx.mock.id},
            {"UPDATE users SET demo_organization_id = '#{ctx.org_id}' WHERE id = $1",
             ctx.outsider.id}
          ] do
        assert_raise Postgrex.Error, ~r/stays a mock person/, fn ->
          Palee.Repo.transaction(fn -> Palee.Repo.query!(sql, [Ecto.UUID.dump!(id)]) end)
        end
      end
    end

    test "removing the demo data deletes every marked person, recorded or not", ctx do
      sql!("DELETE FROM demo_records WHERE source = 'users' AND record_id = $1", [
        uuid(ctx.mock.id)
      ])

      ctx.as.(ctx.owner)
      |> put_req_header("content-type", "application/json")
      |> delete("/api/org/#{ctx.slug}/admin/business/demo-data")
      |> json_response(200)

      assert Identity.demo_user_ids(ctx.org_id) == []
      assert Identity.find_by_id(ctx.mock.id) == nil
      assert Identity.find_by_id(ctx.owner.id)
    end

    test "mock people stay muted by the mark alone", ctx do
      assert Palee.BusinessAccounts.notification_suppressed?(nil, ctx.mock.id)
      refute Palee.BusinessAccounts.notification_suppressed?(nil, ctx.outsider.id)
    end
  end

  describe "visibility" do
    test "only the person and its demo business's active staff see a mock person", ctx do
      ids = [ctx.outsider.id | ctx.mock_ids]

      assert Identity.visible_user_ids(ids, ctx.owner.id) == ids
      assert Identity.visible_user_ids(ids, ctx.outsider.id) == [ctx.outsider.id]
      assert Identity.visible_user_ids(ids, nil) == [ctx.outsider.id]
      assert Identity.visible_to?(ctx.mock.id, ctx.mock.id)
      refute Identity.visible_to?(ctx.mock.id, ctx.outsider.id)
      assert Identity.visible_user_ids([], ctx.owner.id) == []

      # A plain member of the demo business is not its staff.
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: ctx.org_id,
          user_id: ctx.outsider.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      refute Identity.visible_to?(ctx.mock.id, ctx.outsider.id)
    end
  end

  describe "discovery paths" do
    test "global user and athlete search never list mock people", ctx do
      prefix = handle_prefix(ctx.mock)

      refute Enum.any?(Identity.search_users(ctx.mock.handle), &(&1.id in ctx.mock_ids))
      refute Enum.any?(Identity.search_users(prefix), &(&1.id in ctx.mock_ids))
      refute Enum.any?(Identity.search_users(""), &(&1.id in ctx.mock_ids))
      refute Enum.any?(SearchUsers.call("_demo_"), &(&1.id in ctx.mock_ids))
      refute Enum.any?(Identity.search_athletes("_demo_"), &(&1.id in ctx.mock_ids))
      refute Enum.any?(Identity.search_athletes(nil), &(&1.id in ctx.mock_ids))
    end

    test "the vendor's user search never lists mock people", ctx do
      vendor = user_fixture()
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

      %{"users" => users} =
        ctx.as.(vendor)
        |> get("/api/me/search/users?q=#{URI.encode_www_form(ctx.mock.handle)}")
        |> json_response(200)

      assert users == []
    end

    test "the staff's in-business search still finds them", ctx do
      {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, ctx.slug)
      found = SearchUsers.call(handle_prefix(ctx.mock), context)
      assert Enum.any?(found, &(&1.id == ctx.mock.id))
    end

    test "a mock person's profile is a 404 outside its demo business", ctx do
      path = "/api/people/#{ctx.mock.id}"
      assert ctx.as.(ctx.outsider) |> get(path) |> json_response(404)
      assert ctx.as.(ctx.outsider) |> get(path <> "/posts") |> json_response(404)
      assert %{"id" => id} = ctx.as.(ctx.owner) |> get(path) |> json_response(200)
      assert id == ctx.mock.id

      assert {:error, :not_found} = SocialProfile.person(%{user_id: ctx.outsider.id}, ctx.mock.id)
    end

    test "a mock person cannot be followed from outside", ctx do
      assert {:error, _reason} =
               Follows.follow(%{user_id: ctx.outsider.id}, "user", ctx.mock.id)

      assert {:ok, %{status: "requested"}} =
               Follows.follow(%{user_id: ctx.outsider.id}, "user", ctx.owner.id)
    end

    test "the exact-nickname PR grantee lookup answers as for an unknown nickname", ctx do
      assert {:ok, %{grantee: nil}} =
               FindPRGrantee.call(%{user_id: ctx.outsider.id}, ctx.mock.handle)

      assert {:ok, %{grantee: %{id: id}}} =
               FindPRGrantee.call(%{user_id: ctx.owner.id}, ctx.mock.handle)

      assert id == ctx.mock.id
    end

    test "buddy candidates skip mock people for a plain member, not for staff", ctx do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: ctx.org_id,
          user_id: ctx.outsider.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      term = handle_prefix(ctx.mock)

      as_owner = Buddies.candidates(%{user_id: ctx.owner.id}, term, 50)
      assert Enum.any?(as_owner, &(&1.user_id == ctx.mock.id))

      as_member = Buddies.candidates(%{user_id: ctx.outsider.id}, term, 50)
      refute Enum.any?(as_member, &(&1.user_id in ctx.mock_ids))
    end

    test "Γύρω μου's people posts leave mock people out", ctx do
      hood = Ecto.UUID.generate()

      sql!(
        """
        INSERT INTO places_neighbourhoods
          (id, slug, kind, name, name_en, country_code, latitude, longitude, radius_m,
           search_key, inserted_at, updated_at)
        VALUES ($1, $2, 'neighbourhood', 'Κυψέλη', 'Kypseli', 'GR', 38.0, 23.73, 800,
                'kypseli', now(), now())
        """,
        [uuid(hood), "kypseli-#{System.unique_integer([:positive])}"]
      )

      for user_id <- [ctx.outsider.id, ctx.mock.id] do
        sql!(
          """
          INSERT INTO user_home_areas (id, user_id, neighbourhood_id, position, inserted_at, updated_at)
          VALUES ($1, $2, $3, 0, now(), now())
          """,
          [uuid(Ecto.UUID.generate()), uuid(user_id), uuid(hood)]
        )

        sql!(
          """
          INSERT INTO community_social_settings (user_id, visible_around, inserted_at, updated_at)
          VALUES ($1, true, now(), now())
          """,
          [uuid(user_id)]
        )

        sql!(
          """
          INSERT INTO community_profile_posts (id, user_id, audience, body, inserted_at, updated_at)
          VALUES ($1, $2, 'public', 'Καλημέρα', now(), now())
          """,
          [uuid(Ecto.UUID.generate()), uuid(user_id)]
        )
      end

      %{rows: rows} =
        sql!(
          """
          SELECT author_id FROM palee_around_match_posts(
            palee_geo_point(38.0, 23.73), 5000,
            ST_Expand(palee_geo_point(38.0, 23.73)::geometry, 1)::geography,
            now() - interval '1 day', NULL, NULL, NULL, NULL, NULL, NULL, NULL)
          WHERE source = 'profile'
          """,
          []
        )

      authors = Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
      assert ctx.outsider.id in authors
      refute ctx.mock.id in authors
    end
  end

  test "a direct thread to a mock person looks like an unknown person outside the business",
       %{outsider: outsider, mock: mock} do
    params = %{context_type: :direct, participant_id: mock.id}

    assert {:error, :not_found} =
             Palee.Application.GetOrCreateMessagingThread.call(outsider, params)
  end
end
