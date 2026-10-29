defmodule PaleeWeb.AdminSetupControllerTest do
  @moduledoc """
  ADR-255 over HTTP: the settings catalog with its «Προχωρημένα» flag, the
  setup recipes, a dry-run preview and the owner-only apply.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 2]

  setup %{conn: conn} do
    {organization, owner, _context} = organization_fixture()
    {admin, _admin_context} = member_context(organization, :admin)
    {coach, _coach_context} = member_context(organization, :coach)

    %{
      owner: put_bearer_token(conn, owner),
      admin: put_bearer_token(conn, admin),
      coach: put_bearer_token(conn, coach),
      base: "/api/org/#{organization.slug}/admin"
    }
  end

  defp post_json(conn, path),
    do:
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(path, "{}")

  test "GET /setup/settings lists every setting with its level", %{owner: owner, base: base} do
    body = owner |> get(base <> "/setup/settings") |> json_response(200)

    grace = Enum.find(body["settings"], &(&1["key"] == "finance.subscription_grace_days"))
    assert %{"advanced" => true, "verdict" => "advanced", "section" => "finance"} = grace

    capacity = Enum.find(body["settings"], &(&1["key"] == "scheduling.default_capacity"))
    assert %{"advanced" => false, "verdict" => "basic", "default" => 12} = capacity

    assert "finance.subscription_grace_days" in body["advanced_settings"]
    assert body["counts"]["basic"] > 0
  end

  test "GET /settings carries the advanced keys", %{owner: owner, base: base} do
    body = owner |> get(base <> "/settings") |> json_response(200)
    assert "finance.subscription_grace_days" in body["advanced_settings"]
    refute "scheduling.default_capacity" in body["advanced_settings"]
  end

  test "GET /setup/recipes lists the recipes for staff with manage_settings", %{
    owner: owner,
    admin: admin,
    base: base
  } do
    body = owner |> get(base <> "/setup/recipes") |> json_response(200)
    keys = Enum.map(body["recipes"], & &1["key"])
    assert "crossfit_box" in keys and "independent_coach" in keys
    assert body["can_apply"] == true
    assert body["applications"] == []
    assert body["currency"] =~ ~r/^[A-Z]{3}$/

    crossfit = Enum.find(body["recipes"], &(&1["key"] == "crossfit_box"))
    assert crossfit["names"] == %{"en" => "CrossFit box", "el" => "CrossFit box"}
    assert Enum.any?(crossfit["packages"], &(&1["code"] == "setup_unlimited"))

    assert %{"can_apply" => false} = admin |> get(base <> "/setup/recipes") |> json_response(200)
  end

  test "preview, apply, apply again", %{owner: owner, base: base} do
    preview = owner |> post_json(base <> "/setup/recipes/open_gym/preview") |> json_response(200)
    assert preview["change_count"] > 0
    assert Enum.any?(preview["changes"], &(&1["key"] == "check_in.desk_override"))

    applied = owner |> post_json(base <> "/setup/recipes/open_gym/apply") |> json_response(200)
    assert applied["plan"]["change_count"] == preview["change_count"]
    assert applied["application"]["recipe_key"] == "open_gym"
    assert applied["application"]["change_count"] == preview["change_count"]

    again = owner |> post_json(base <> "/setup/recipes/open_gym/apply") |> json_response(200)
    assert again["plan"]["changes"] == []
    assert again["application"]["change_count"] == 0

    history = owner |> get(base <> "/setup/recipes") |> json_response(200)
    assert [%{"change_count" => 0}, %{"recipe_key" => "open_gym"}] = history["applications"]
  end

  test "apply takes the owner's prices from the preview", %{owner: owner, base: base} do
    body = Jason.encode!(%{prices: %{"setup_unlimited" => 7_500}})

    applied =
      owner
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(base <> "/setup/recipes/crossfit_box/apply", body)
      |> json_response(200)

    unlimited = Enum.find(applied["plan"]["changes"], &(&1["key"] == "package.setup_unlimited"))
    assert unlimited["to"] == 7_500

    bad = Jason.encode!(%{prices: %{"setup_bowling" => 100}})

    assert %{"code" => "invalid_recipe_prices"} =
             owner
             |> recycle()
             |> put_req_header("content-type", "application/json")
             |> post(base <> "/setup/recipes/functional_hyrox/apply", bad)
             |> json_response(422)
  end

  test "the preview marks the owner's own values; defaults_only keeps them", %{
    owner: owner,
    base: base
  } do
    owner
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> patch(base <> "/settings", Jason.encode!(%{scheduling: %{default_capacity: 20}}))
    |> json_response(200)

    preview =
      owner
      |> recycle()
      |> post_json(base <> "/setup/recipes/crossfit_box/preview")
      |> json_response(200)

    capacity = Enum.find(preview["changes"], &(&1["key"] == "scheduling.default_capacity"))
    assert %{"from" => 20, "to" => 16, "owner_changed" => true} = capacity
    assert preview["kept"] == []

    applied =
      owner
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        base <> "/setup/recipes/crossfit_box/apply",
        Jason.encode!(%{mode: "defaults_only"})
      )
      |> json_response(200)

    assert applied["plan"]["kept"] == ["scheduling.default_capacity"]
    refute Enum.any?(applied["plan"]["changes"], &(&1["key"] == "scheduling.default_capacity"))

    settings = owner |> recycle() |> get(base <> "/settings") |> json_response(200)
    assert settings["scheduling"]["default_capacity"] == 20

    assert owner
           |> recycle()
           |> put_req_header("content-type", "application/json")
           |> post(base <> "/setup/recipes/crossfit_box/apply", Jason.encode!(%{mode: "some"}))
           |> json_response(422)
  end

  test "only the owner applies; a coach cannot see recipes", %{
    admin: admin,
    coach: coach,
    base: base
  } do
    assert %{"code" => "recipe_owner_only"} =
             admin |> post_json(base <> "/setup/recipes/open_gym/apply") |> json_response(403)

    assert coach |> get(base <> "/setup/recipes") |> response(403)
  end

  test "an unknown recipe is 404", %{owner: owner, base: base} do
    assert %{"code" => "recipe_not_found"} =
             owner
             |> post_json(base <> "/setup/recipes/bowling_alley/preview")
             |> json_response(404)
  end

  test "the responses match the OpenAPI spec", %{owner: owner, base: base} do
    spec = PaleeWeb.ApiSpec.spec()
    recipes = owner |> get(base <> "/setup/recipes") |> json_response(200)
    assert {:ok, _} = OpenApiSpex.cast_value(recipes, PaleeWeb.Schemas.Setup.recipes(), spec)

    catalog = owner |> get(base <> "/setup/settings") |> json_response(200)

    assert {:ok, _} =
             OpenApiSpex.cast_value(catalog, PaleeWeb.Schemas.Setup.settings_catalog(), spec)

    applied =
      owner |> post_json(base <> "/setup/recipes/crossfit_box/apply") |> json_response(200)

    assert {:ok, _} = OpenApiSpex.cast_value(applied, PaleeWeb.Schemas.Setup.applied(), spec)

    paths = spec.paths
    assert paths["/api/org/{organization_slug}/admin/setup/recipes/{key}/apply"].post
    assert paths["/api/org/{organization_slug}/admin/setup/settings"].get
  end
end
