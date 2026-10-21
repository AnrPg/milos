defmodule PaleeWeb.AdminPublicProfileControllerTest do
  @moduledoc "ADR-142/ADR-148 public profile editor endpoints, as the RLS runtime role."

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.Organizations
  alias Palee.TestSupport.MemoryObjectStore

  setup do
    MemoryObjectStore.start()
    owner = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Public Gym #{System.unique_integer([:positive])}"
      })

    add_member(organization, owner, :owner)
    member = user_fixture()
    add_member(organization, member, :member)
    %{owner: owner, member: member, base: "/api/org/#{organization.slug}/admin/public-profile"}
  end

  test "owner uploads a photo and publishes the profile", ctx do
    upload =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> post("#{ctx.base}/photos", %{content_type: "image/jpeg", byte_size: 200})
      |> json_response(200)

    [_, key] = Regex.run(~r|/media_public/([^?]+)\?|, upload["upload_url"])
    :ok = MemoryObjectStore.put_object(:media_public, key, jpeg(1200, 800), "image/jpeg")

    assert %{"media" => %{"id" => id, "status" => "ready", "width" => 1200}} =
             ctx.conn
             |> put_bearer_token(ctx.owner)
             |> post("#{ctx.base}/photos/#{upload["media_id"]}/complete")
             |> json_response(200)

    assert %{"profile" => %{"published" => false, "missing" => [], "cover" => %{"id" => ^id}}} =
             ctx.conn
             |> put_bearer_token(ctx.owner)
             |> put(ctx.base, %{
               about: "Box",
               disciplines: ["crossfit"],
               amenities: ["showers"],
               cover_photo_id: id
             })
             |> json_response(200)

    assert %{"profile" => %{"published" => true, "unpublished_changes" => false}} =
             ctx.conn
             |> put_bearer_token(ctx.owner)
             |> post("#{ctx.base}/publish", %{})
             |> json_response(200)

    assert %{"suggestion" => %{"status" => "pending"}} =
             ctx.conn
             |> put_bearer_token(ctx.owner)
             |> post("#{ctx.base}/suggestions", %{list: "amenities", name: "Ice bath"})
             |> json_response(201)

    assert %{"profile" => %{"published" => false}} =
             ctx.conn
             |> put_bearer_token(ctx.owner)
             |> post("#{ctx.base}/unpublish")
             |> json_response(200)

    assert %{"profile" => %{"about" => "Box", "disciplines" => ["crossfit"]}} =
             ctx.conn |> put_bearer_token(ctx.owner) |> get(ctx.base) |> json_response(200)
  end

  test "unknown disciplines are rejected by the contract", ctx do
    ctx.conn
    |> put_bearer_token(ctx.owner)
    |> put(ctx.base, %{disciplines: ["quidditch"]})
    |> json_response(422)
  end

  test "the vocabulary is public and grouped", ctx do
    assert %{"discipline_groups" => [%{"key" => "strength", "items" => ["strength" | _]} | _]} =
             ctx.conn |> get("/api/box-vocabulary") |> json_response(200)
  end

  test "members cannot reach the editor", ctx do
    ctx.conn |> put_bearer_token(ctx.member) |> get(ctx.base) |> json_response(403)
  end

  defp add_member(organization, user, role) do
    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
