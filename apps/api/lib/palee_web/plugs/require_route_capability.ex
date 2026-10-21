defmodule PaleeWeb.Plugs.RequireRouteCapability do
  @moduledoc """
  Lets a staff request through when the tenant context holds one of the
  capabilities `RouteCapabilities` lists for the matched controller action
  (ADR-099). An unlisted action is refused.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Palee.Organizations.Domain.TenantAuthorization
  alias PaleeWeb.RouteCapabilities

  def init(opts), do: opts

  # Pipelines run before Phoenix records the controller and action on the
  # conn, so the matched route is looked up here.
  defp route(conn) do
    case Phoenix.Router.route_info(
           PaleeWeb.Router,
           conn.method,
           conn.request_path,
           conn.host
         ) do
      %{plug: controller, plug_opts: action} -> {controller, action}
      _no_route -> nil
    end
  end

  def call(conn, _opts) do
    context = conn.assigns[:tenant_context]

    capabilities =
      case route(conn) do
        {controller, action} -> RouteCapabilities.for_action(controller, action) || []
        nil -> []
      end

    if context && Enum.any?(capabilities, &TenantAuthorization.can?(context, &1)) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{code: "forbidden", error: "Forbidden"})
      |> halt()
    end
  end
end
