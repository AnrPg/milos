defmodule PaleeWeb.RoleAccessController do
  @moduledoc "What the gym unlocks for roles such as front desk (ADR-099)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Organizations
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Role access"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @grants %Schema{
    type: :object,
    additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
  }

  @response %Schema{
    type: :object,
    properties: %{grants: @grants, grantable: @grants},
    required: [:grants, :grantable]
  }

  operation(:show,
    summary: "Capabilities this gym unlocked per role, and what can be unlocked",
    responses: [ok: {"Role access", "application/json", @response}]
  )

  def show(conn, _params) do
    with {:ok, grants} <- Organizations.get_role_grants(conn.assigns.tenant_context) do
      json(conn, %{grants: grants, grantable: Organizations.grantable_capabilities()})
    end
  end

  operation(:update,
    summary: "Set what a role may do beyond its defaults in this gym",
    parameters: [
      %Parameter{name: :role, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{capabilities: %Schema{type: :array, items: %Schema{type: :string}}},
            required: [:capabilities]
          }
        }
      }
    },
    responses: [ok: {"Role access", "application/json", @response}]
  )

  def update(conn, %{role: role}) do
    capabilities = Map.get(conn.body_params, :capabilities, [])

    with {:ok, grants} <-
           Organizations.set_role_grants(conn.assigns.tenant_context, role, capabilities) do
      json(conn, %{grants: grants, grantable: Organizations.grantable_capabilities()})
    end
  end
end
