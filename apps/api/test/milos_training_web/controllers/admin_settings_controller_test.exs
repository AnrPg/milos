defmodule MilosTrainingWeb.AdminSettingsControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations

  test "admin can patch only the global theme", %{conn: conn} do
    admin = admin_fixture()
    organization = org_with_owner!(admin)

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/settings",
        %{gamification: %{theme_slug: "aurora"}}
      )
      |> json_response(200)

    assert get_in(payload, ["gamification", "theme_slug"]) == "aurora"
    assert get_in(payload, ["gamification", "weekly_workout_target"]) == 2
    assert get_in(payload, ["gamification", "leaderboard_enabled"]) == true
    assert get_in(payload, ["notifications", "enabled"]) == false

    # TD-092: reading the settings back (and a save that leaves gamification
    # untouched) sees the gym's stored values, not the defaults.
    fetched =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/settings")
      |> json_response(200)

    assert get_in(fetched, ["gamification", "theme_slug"]) == "aurora"

    untouched =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/org/#{organization.slug}/admin/settings", %{
        finance: %{payment_reminder_interval_days: 5}
      })
      |> json_response(200)

    assert get_in(untouched, ["gamification", "theme_slug"]) == "aurora"
  end

  test "admin can configure browser push service settings", %{conn: conn} do
    admin = admin_fixture()
    organization = org_with_owner!(admin)

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/settings",
        %{
          notifications: %{
            vapid_public_key: "public-key",
            vapid_private_key: "private-key",
            vapid_subject: "mailto:gym@example.test"
          }
        }
      )
      |> json_response(200)

    assert get_in(payload, ["notifications", "enabled"]) == true
    assert get_in(payload, ["notifications", "vapid_public_key"]) == "public-key"
    assert get_in(payload, ["notifications", "vapid_private_key_configured"]) == true
    refute Map.has_key?(payload["notifications"], "vapid_private_key")

    push_config =
      conn
      |> put_bearer_token(admin)
      |> get("/api/notifications/push-config")
      |> json_response(200)

    assert push_config == %{"enabled" => true, "vapid_public_key" => "public-key"}
  end

  test "a gym's first finance settings save is stored for that gym", %{conn: conn} do
    admin = admin_fixture()
    organization = org_with_owner!(admin)
    MilosTraining.Repo.query!("SELECT set_config('app.organization_id', '', false)")

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/settings",
        %{finance: %{package_modules: ["group_classes", "open_gym"]}}
      )
      |> json_response(200)

    assert get_in(payload, ["finance", "package_modules"]) == ["group_classes", "open_gym"]
    assert get_in(payload, ["finance", "organization_id"]) == organization.id
  end

  test "the owner marks the organization as an independent coach (ADR-162)", %{conn: conn} do
    owner = admin_fixture()
    organization = org_with_owner!(owner)
    admin = admin_fixture()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :admin,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    path = "/api/org/#{organization.slug}/admin/settings"
    as = fn user -> conn |> recycle() |> put_bearer_token(user) end

    assert %{"kind" => "gym", "editable" => true} =
             as.(owner) |> get(path) |> json_response(200) |> Map.fetch!("provider")

    assert %{"kind" => "coach", "editable" => true} =
             as.(owner)
             |> patch(path, %{provider: %{kind: "coach"}})
             |> json_response(200)
             |> Map.fetch!("provider")

    # Members see it in Box ▾.
    assert [%{kind: "coach"}] =
             MilosTraining.Organizations.list_my_providers(%{user_id: owner.id})
             |> Enum.filter(&(&1.organization_id == organization.id))

    # An admin reads it but cannot change it, and the whole save is refused.
    assert %{"kind" => "coach", "editable" => false} =
             as.(admin) |> get(path) |> json_response(200) |> Map.fetch!("provider")

    assert as.(admin)
           |> patch(path, %{provider: %{kind: "gym"}, gamification: %{theme_slug: "aurora"}})
           |> json_response(403)

    assert as.(owner) |> get(path) |> json_response(200) |> get_in(["gamification", "theme_slug"]) !=
             "aurora"

    assert as.(owner) |> patch(path, %{provider: %{kind: "studio"}}) |> json_response(422)
  end

  defp org_with_owner!(owner) do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Settings Gym #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    organization
  end
end
