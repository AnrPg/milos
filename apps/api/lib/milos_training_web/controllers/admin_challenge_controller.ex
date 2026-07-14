defmodule MilosTrainingWeb.AdminChallengeController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    CreateSeasonalChallenge,
    DeleteSeasonalChallenge,
    GetAdminChallenge,
    ListAdminChallenges,
    UpdateSeasonalChallenge
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Challenges"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create, :update, :delete]

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @challenge_payload_schema %Schema{
    type: :object,
    required: [
      :title,
      :criteria_type,
      :criteria_value,
      :badge_key,
      :badge_label,
      :starts_at,
      :ends_at
    ],
    properties: %{
      title: %Schema{type: :string},
      description: %Schema{type: :string, nullable: true},
      criteria_type: %Schema{
        type: :string,
        enum: ["workout_count", "workout_type_count", "pr_count", "custom"]
      },
      criteria_value: %Schema{
        oneOf: [
          %Schema{
            type: :object,
            properties: %{
              count: %Schema{type: :integer, minimum: 1}
            },
            required: [:count],
            additionalProperties: false
          },
          %Schema{
            type: :object,
            properties: %{
              count: %Schema{type: :integer, minimum: 1},
              type_filter: %Schema{
                type: :string,
                enum: [
                  "crossfit",
                  "strength",
                  "gymnastics",
                  "aerobics",
                  "flexibility",
                  "recovery"
                ]
              }
            },
            required: [:count, :type_filter],
            additionalProperties: false
          },
          %Schema{
            type: :object,
            properties: %{
              count: %Schema{type: :integer, minimum: 1},
              increment_per_completion: %Schema{type: :integer, minimum: 1}
            },
            required: [:count, :increment_per_completion],
            additionalProperties: false
          }
        ]
      },
      badge_key: %Schema{type: :string},
      badge_label: %Schema{type: :string},
      starts_at: %Schema{type: :string, format: :date},
      ends_at: %Schema{type: :string, format: :date}
    }
  }

  @participant_schema %Schema{
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      nickname: %Schema{type: :string, nullable: true},
      role: %Schema{type: :string, nullable: true},
      progress: %Schema{type: :integer},
      target: %Schema{type: :integer},
      completion_ratio: %Schema{type: :number},
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:user_id, :progress, :target, :completion_ratio, :updated_at]
  }

  operation(:index,
    summary: "List seasonal challenges with progress summaries",
    responses: [
      ok:
        {"Challenges", "application/json",
         %Schema{
           type: :object,
           properties: %{challenges: %Schema{type: :array, items: %Schema{type: :object}}},
           required: [:challenges]
         }}
    ]
  )

  operation(:show,
    summary: "Get a seasonal challenge with participant progress",
    parameters: [@id_param],
    responses: [
      ok:
        {"Challenge", "application/json",
         %Schema{
           type: :object,
           properties: %{
             challenge: %Schema{type: :object, additionalProperties: true},
             participants: %Schema{type: :array, items: @participant_schema}
           },
           required: [:challenge, :participants]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def index(conn, _params) do
    with {:ok, challenges} <- ListAdminChallenges.call() do
      json(conn, %{challenges: challenges})
    end
  end

  operation(:create,
    summary: "Create a seasonal challenge",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @challenge_payload_schema}}
    },
    responses: [
      created: {"Challenge", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:update,
    summary: "Update a seasonal challenge",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @challenge_payload_schema}}
    },
    responses: [
      ok: {"Challenge", "application/json", %Schema{type: :object}},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def create(conn, params) do
    admin = GuardianPlug.current_resource(conn)

    with {:ok, challenge} <- CreateSeasonalChallenge.call(admin.id, body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{challenge: challenge})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, payload} <- GetAdminChallenge.call(id) do
      json(conn, payload)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, challenge} <- UpdateSeasonalChallenge.call(id, body_params(conn, params)) do
      json(conn, %{challenge: challenge})
    end
  end

  operation(:delete,
    summary: "Delete a seasonal challenge",
    parameters: [@id_param],
    responses: [
      no_content: {"Deleted", "application/json", nil},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def delete(conn, %{"id" => id}) do
    with :ok <- DeleteSeasonalChallenge.call(id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp body_params(conn, params), do: conn.body_params || Map.drop(params, ["id", :id])
end
