defmodule PaleeWeb.MyPlacesControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.Application.SetHomeLocation
  alias Palee.{Facility, Organizations, Repo}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    owner_context = context_for(owner, :owner)

    {:ok, kypseli} =
      Facility.create_location(owner_context, %{
        name: "Κυψέλη",
        latitude: 38.0035,
        longitude: 23.7385
      })

    {:ok, patisia} =
      Facility.create_location(owner_context, %{
        name: "Πατήσια",
        latitude: 38.0215,
        longitude: 23.7330
      })

    {:ok, closed} = Facility.create_location(owner_context, %{name: "Παλιό"})
    {:ok, _} = Facility.archive_location(owner_context, closed.id)

    member = user_fixture()
    member_context = context_for(member, nil)
    {:ok, _} = SetHomeLocation.call(member_context, member.id, kypseli.id)

    %{conn: put_bearer_token(conn, member), kypseli: kypseli, patisia: patisia}
  end

  defp context_for(actor, role) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  test "lists bookable locations nearest to the home location by default", %{
    conn: conn,
    kypseli: kypseli,
    patisia: patisia
  } do
    places = conn |> get("/api/me/places") |> json_response(200) |> Map.fetch!("places")

    assert [
             %{"id" => first_id, "home" => true, "distance_km" => +0.0},
             %{"id" => second_id, "home" => false, "distance_km" => km}
           ] = places

    assert first_id == kypseli.id
    assert second_id == patisia.id
    assert km > 1.5 and km < 2.5
    assert %{"slug" => _, "name" => _} = hd(places)["organization"]
  end

  test "sorts by distance from the device when given", %{conn: conn, patisia: patisia} do
    places =
      conn
      |> get("/api/me/places?lat=38.0230&lng=23.7320")
      |> json_response(200)
      |> Map.fetch!("places")

    assert hd(places)["id"] == patisia.id

    conn |> recycle() |> get("/api/me/places?lat=120&lng=0") |> json_response(422)
  end
end
