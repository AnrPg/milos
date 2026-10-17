defmodule MilosTrainingWeb.HomeLocationController do
  @moduledoc "A person's home location in a gym (Phase 2): set by themselves or by staff."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.SetHomeLocation
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Locations"])
  security([%{"bearerAuth" => []}])

  @request %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            location_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: true,
              description: "An active location of the gym, or null to clear."
            }
          },
          required: [:location_id]
        }
      }
    }
  }

  @response %Schema{
    type: :object,
    properties: %{
      membership: %Schema{
        type: :object,
        properties: %{
          user_id: %Schema{type: :string, format: :uuid},
          home_location_id: %Schema{type: :string, format: :uuid, nullable: true}
        },
        required: [:user_id, :home_location_id]
      }
    },
    required: [:membership]
  }

  operation(:update_mine,
    summary: "Set my home location in this gym",
    request_body: @request,
    responses: [ok: {"Membership", "application/json", @response}]
  )

  def update_mine(conn, _params) do
    context = conn.assigns.tenant_context
    set(conn, context.user_id, location_id(conn))
  end

  operation(:update_member,
    summary: "Set a member's home location (staff who manage memberships)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: @request,
    responses: [ok: {"Membership", "application/json", @response}]
  )

  def update_member(conn, params) do
    set(conn, params["id"] || params[:id], location_id(conn))
  end

  defp set(conn, user_id, location_id) do
    with {:ok, membership} <-
           SetHomeLocation.call(conn.assigns.tenant_context, user_id, location_id) do
      json(conn, %{
        membership: %{
          user_id: membership.user_id,
          home_location_id: membership.home_location_id
        }
      })
    end
  end

  defp location_id(conn),
    do: Map.get(conn.body_params, "location_id", Map.get(conn.body_params, :location_id))
end
