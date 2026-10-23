defmodule PaleeWeb.StaffLocationScopeController do
  @moduledoc "Admin › Χρήστες: the branches a staff member works at (ADR-186)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.SetStaffLocationScope
  alias PaleeWeb.Schemas.LocationScope
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Users"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @error %Schema{type: :object, additionalProperties: true}

  operation(:update,
    summary: "Set the branches someone works at as staff («Όλα τα καταστήματα» or a list)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: LocationScope.request_schema()}}
    },
    responses: [
      ok:
        {"Scope", "application/json",
         %Schema{
           type: :object,
           properties: %{
             user_id: %Schema{type: :string, format: :uuid},
             location_scope: LocationScope.schema()
           },
           required: [:user_id, :location_scope]
         }},
      forbidden: {"Beyond your own branches or roles", "application/json", @error},
      unprocessable_entity: {"Invalid scope", "application/json", @error}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, result} <-
           SetStaffLocationScope.call(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end
end
