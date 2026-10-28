defmodule PaleeWeb.MyRolesController do
  @moduledoc """
  Settings › «Οι ρόλοι μου» (ADR-219): a person adds or drops roles below
  their own top role in this gym, e.g. an owner who also coaches. The top
  role never changes here.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Roles"])
  security([%{"bearerAuth" => []}])

  operation(:update,
    summary: "Set my roles in this gym; only roles below my top role may change (ADR-219)",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              roles: %Schema{
                type: :array,
                minItems: 1,
                items: %Schema{
                  type: :string,
                  enum: Enum.map(Palee.Organizations.roles(), &to_string/1)
                }
              }
            },
            required: [:roles]
          }
        }
      }
    },
    responses: [
      ok:
        {"Membership", "application/json",
         %Schema{
           type: :object,
           properties: %{
             membership: %Schema{
               type: :object,
               properties: %{
                 user_id: %Schema{type: :string, format: :uuid},
                 role: %Schema{type: :string},
                 roles: %Schema{type: :array, items: %Schema{type: :string}}
               },
               required: [:role, :roles, :user_id]
             }
           },
           required: [:membership]
         }},
      forbidden:
        {"A role at or above my top role (own_top_role_locked)", "application/json",
         %Schema{type: :object}}
    ]
  )

  def update(conn, _params) do
    context = conn.assigns.tenant_context
    roles = Map.get(conn.body_params, :roles) || Map.get(conn.body_params, "roles")

    with {:ok, membership} <-
           Palee.Application.ChangeMembershipRoles.set_roles(context, context.user_id, roles) do
      json(conn, %{
        membership: %{
          user_id: membership.user_id,
          role: to_string(membership.role),
          roles: Enum.map(membership.roles, &to_string/1)
        }
      })
    end
  end
end
