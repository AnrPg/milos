defmodule MilosTrainingWeb.AdminSearchController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.AdminSearchUsers
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Search"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Search users with finance membership metadata",
    parameters: [
      %Parameter{name: :q, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :role,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["member", "athlete", "all"]}
      },
      %Parameter{
        name: :membership_status,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :package_code,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :package_family,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :user_type,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["member", "athlete"]}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      }
    ],
    responses: [
      ok:
        {"Search results", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def index(conn, params) do
    with {:ok, payload} <- AdminSearchUsers.call(params) do
      json(conn, payload)
    end
  end
end
