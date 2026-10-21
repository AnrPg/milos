defmodule PaleeWeb.RouteCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.AccessPolicy
  alias PaleeWeb.RouteCapabilities

  @staff_prefixes ["/api/org/:organization_slug/admin", "/api/org/:organization_slug/staff"]

  test "every staff route names capabilities that exist (ADR-099)" do
    known = MapSet.new(AccessPolicy.all_capabilities())

    staff_routes =
      PaleeWeb.Router.__routes__()
      |> Enum.filter(fn route ->
        Enum.any?(@staff_prefixes, &String.starts_with?(route.path, &1))
      end)

    assert staff_routes != []

    for route <- staff_routes do
      capabilities = RouteCapabilities.for_action(route.plug, route.plug_opts)
      assert capabilities, "#{route.verb} #{route.path} has no capability"
      for capability <- capabilities, do: assert(capability in known, inspect(capability))
    end
  end
end
