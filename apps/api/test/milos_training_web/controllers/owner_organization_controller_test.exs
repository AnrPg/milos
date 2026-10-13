defmodule MilosTrainingWeb.OwnerOrganizationControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Organizations, Repo}

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    admin = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :admin)

    %{
      conn: conn,
      organization: organization,
      owner: owner,
      admin: admin,
      owner_conn: put_bearer_token(conn, owner),
      admin_conn: put_bearer_token(conn, admin),
      base: "/api/org/#{organization.slug}/admin/organization"
    }
  end

  defp send_json(conn, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  test "only owners create gyms, and they own the new one", ctx do
    assert %{"slug" => "second-gym", "id" => second_gym_id} =
             ctx.owner_conn
             |> send_json("/api/organizations", %{name: "Second Gym"})
             |> json_response(201)

    # ADR-133: the new gym starts with the default scale levels (ADR-128).
    assert ["scaled", "rx", "rx-plus"] ==
             %{organization_id: second_gym_id, user_id: ctx.owner.id}
             |> MilosTraining.Workouts.list_scale_levels()
             |> Enum.map(& &1.slug)

    slugs =
      ctx.owner_conn
      |> recycle()
      |> get("/api/memberships")
      |> json_response(200)
      |> Enum.map(& &1["organization"]["slug"])

    assert "second-gym" in slugs

    assert %{"code" => "owner_required"} =
             ctx.admin_conn
             |> send_json("/api/organizations", %{name: "Admin Gym"})
             |> json_response(403)
  end

  test "an owner hands over ownership and stays as admin", ctx do
    assert ctx.admin_conn
           |> send_json("#{ctx.base}/transfer", %{user_id: ctx.owner.id})
           |> json_response(403)

    assert %{"slug" => _slug} =
             ctx.owner_conn
             |> send_json("#{ctx.base}/transfer", %{user_id: ctx.admin.id})
             |> json_response(200)

    assert [:admin, :owner] ==
             Enum.sort(Organizations.member_roles(ctx.organization.id, ctx.admin.id))

    assert [:admin] == Organizations.member_roles(ctx.organization.id, ctx.owner.id)
  end

  test "archiving needs the slug and closes the gym", ctx do
    assert %{"code" => "confirmation_mismatch"} =
             ctx.owner_conn
             |> send_json("#{ctx.base}/archive", %{confirm: "nope"})
             |> json_response(422)

    assert %{"status" => "archived"} =
             ctx.owner_conn
             |> send_json("#{ctx.base}/archive", %{confirm: ctx.organization.slug})
             |> json_response(200)
  end
end
