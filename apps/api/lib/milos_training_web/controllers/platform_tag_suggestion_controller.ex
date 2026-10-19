defmodule MilosTrainingWeb.PlatformTagSuggestionController do
  @moduledoc "Platform staff review tags gym owners could not find in the lists (board 3b Q5)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.SuggestBoxTag
  alias MilosTrainingWeb.Schemas.PublicProfile
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Platform"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Pending tag suggestions from every gym",
    responses: [
      ok:
        {"Suggestions", "application/json",
         %Schema{
           type: :object,
           required: [:suggestions],
           properties: %{suggestions: %Schema{type: :array, items: PublicProfile.suggestion()}}
         }}
    ]
  )

  def index(conn, _params) do
    suggestions = Enum.map(SuggestBoxTag.pending(), &Map.put(&1, :status, "pending"))
    json(conn, %{suggestions: suggestions})
  end

  operation(:resolve,
    summary: "Mark a suggestion added to its list or declined",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            required: [:status],
            properties: %{status: %Schema{type: :string, enum: ["added", "declined"]}}
          }
        }
      }
    },
    responses: [
      no_content: "Resolved",
      not_found: {"Not pending", "application/json", %Schema{type: :object}}
    ]
  )

  def resolve(conn, %{id: id}) do
    with :ok <- SuggestBoxTag.resolve(id, conn.body_params.status) do
      send_resp(conn, :no_content, "")
    end
  end
end
