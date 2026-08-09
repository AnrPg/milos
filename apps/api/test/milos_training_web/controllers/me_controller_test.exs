defmodule MilosTrainingWeb.MeControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Identity
  alias MilosTraining.Organizations
  alias MilosTraining.Infrastructure.Auth.Guardian

  describe "PATCH /api/me/avatar" do
    setup do
      original_avatar_storage = Application.fetch_env!(:milos_training, :avatar_storage)
      Application.put_env(:milos_training, :avatar_storage, __MODULE__.AvatarStorage)

      on_exit(fn ->
        Application.put_env(:milos_training, :avatar_storage, original_avatar_storage)
      end)
    end

    test "rejects a missing avatar_key instead of clearing the avatar implicitly", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "avatar_contract_member",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      conn
      |> put_bearer_token(user)
      |> patch("/api/me/avatar", Jason.encode!(%{}))
      |> json_response(422)

      assert Identity.find_by_id(user.id).avatar_url == nil
    end

    test "persists the finalized avatar URL when the cast body contains an avatar_key", %{
      conn: conn
    } do
      {:ok, user} =
        Identity.register(%{
          nickname: "avatar_finalize_member",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      avatar_key = "avatars/#{user.id}/finalized.jpg"

      body =
        conn
        |> put_bearer_token(user)
        |> patch("/api/me/avatar", Jason.encode!(%{avatar_key: avatar_key}))
        |> json_response(200)

      assert body["user"]["avatar_url"] ==
               "https://s3-milos.4kq.net/milos-avatars/#{avatar_key}"

      assert Identity.find_by_id(user.id).avatar_url == body["user"]["avatar_url"]
    end

    test "clears the avatar when the cast body sends an explicit null avatar_key", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "avatar_clear_member",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      body =
        conn
        |> put_bearer_token(user)
        |> patch("/api/me/avatar", Jason.encode!(%{avatar_key: nil}))
        |> json_response(200)

      assert body["user"]["avatar_url"] == nil
      assert Identity.find_by_id(user.id).avatar_url == nil
    end

    defmodule AvatarStorage do
      @behaviour MilosTraining.Application.Ports.AvatarStorage

      @impl true
      def create_upload(_user_id, _content_type, _byte_size), do: {:error, :not_used}

      @impl true
      def validate_uploaded(user_id, "avatars/" <> _rest = key) do
        if String.starts_with?(key, "avatars/#{user_id}/") do
          {:ok, "https://s3-milos.4kq.net/milos-avatars/#{key}"}
        else
          {:error, :avatar_key_forbidden}
        end
      end
    end
  end

  describe "PATCH /api/me/profile language preference" do
    test "persists a supported locale and returns it in the profile response", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "polyglot_member",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(user, %{"sv" => Map.get(user, :security_version, 1)},
          token_type: "access"
        )

      body =
        conn
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/me/profile", Jason.encode!(%{preferred_locale: "ar"}))
        |> json_response(200)

      assert body["user"]["preferred_locale"] == "ar"
      assert Identity.find_by_id(user.id).preferred_locale == "ar"
    end

    test "rejects an unsupported locale without changing the preference", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "locale_guard",
          password: "S3cur3P@ss!42",
          role: :athlete,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(user, %{"sv" => Map.get(user, :security_version, 1)},
          token_type: "access"
        )

      conn
      |> put_req_header("authorization", "Bearer " <> access_token)
      |> put_req_header("content-type", "application/json")
      |> patch("/api/me/profile", Jason.encode!(%{preferred_locale: "pt-BR"}))
      |> json_response(422)

      assert Identity.find_by_id(user.id).preferred_locale == "en"
    end
  end

  describe "GET /api/me/search/users" do
    test "tenant users only see users in the selected organization", %{conn: conn} do
      {:ok, organization} = Organizations.create_organization(%{name: "Tenant Search One"})
      {:ok, other_organization} = Organizations.create_organization(%{name: "Tenant Search Two"})

      searcher = register_search_user("tenant_searcher")
      visible = register_search_user("tenant_visible")
      hidden = register_search_user("tenant_hidden")

      add_membership(organization.id, searcher.id)
      add_membership(organization.id, visible.id)
      add_membership(other_organization.id, hidden.id)

      body =
        conn
        |> put_bearer_token(searcher)
        |> put_req_header("x-organization-slug", organization.slug)
        |> get("/api/me/search/users?q=tenant_")
        |> json_response(200)

      ids = Enum.map(body["users"], & &1["id"])
      assert visible.id in ids
      assert searcher.id in ids
      refute hidden.id in ids
    end

    test "platform owners can search across organizations", %{conn: conn} do
      {:ok, organization} = Organizations.create_organization(%{name: "Platform Search One"})

      {:ok, other_organization} =
        Organizations.create_organization(%{name: "Platform Search Two"})

      vendor = register_search_user("platform_searcher", :admin)
      visible = register_search_user("platform_visible")
      hidden = register_search_user("platform_hidden")

      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
      add_membership(organization.id, visible.id)
      add_membership(other_organization.id, hidden.id)

      body =
        conn
        |> put_bearer_token(vendor)
        |> get("/api/me/search/users?q=platform_")
        |> json_response(200)

      ids = Enum.map(body["users"], & &1["id"])
      assert visible.id in ids
      assert hidden.id in ids
    end
  end

  defp register_search_user(nickname, role \\ :member) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    if role == :admin do
      {:ok, admin} = Identity.update_role(user, :admin)
      admin
    else
      user
    end
  end

  defp add_membership(organization_id, user_id) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization_id,
        user_id: user_id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
