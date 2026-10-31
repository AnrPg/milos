defmodule PaleeWeb.AdminPackageRequestController do
  @moduledoc """
  ADR-291: the front desk's «Περιμένουν πληρωμή»: packages people asked for
  in the app («Το θέλω»), and «Είσπραξη», which records the money and
  assigns the package in one step.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Application.BranchReport
  alias Palee.Application.Finance.PackageRequests
  alias PaleeWeb.Schemas.Payments, as: P

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Finance"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: P.uuid()}

  operation(:index,
    summary: "Packages waiting to be paid at the front desk",
    description:
      "Open requests (held `hold_days` days), oldest first, each with the person who asked.",
    parameters: [PaleeWeb.Schemas.LocationScope.filter_parameter()],
    responses: [ok: {"Package requests", "application/json", P.package_request_list()}]
  )

  def index(conn, params) do
    context = conn.assigns.tenant_context
    report = BranchReport.resolve(context, stringify(params))
    json(conn, %{requests: PackageRequests.for_desk(context, user_ids: report.user_ids)})
  end

  operation(:collect,
    summary: "Take the money for a package waiting at the desk («Είσπραξη»)",
    description:
      "Records the payment (the box's receipt or invoice, ADR-222) and assigns the package " <>
        "from today in one step. Safe to retry.",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: P.package_request_collect_body()}}
    },
    responses: [
      ok:
        {"Collected", "application/json",
         %Schema{
           type: :object,
           properties: %{
             request: P.package_request(),
             received: %Schema{type: :object, additionalProperties: true}
           },
           required: [:received, :request]
         }}
    ]
  )

  def collect(conn, %{id: id}) do
    with {:ok, result} <-
           PackageRequests.collect(
             conn.assigns.tenant_context,
             id,
             Guardian.Plug.current_resource(conn).id,
             conn.body_params
           ) do
      json(conn, result)
    end
  end

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
