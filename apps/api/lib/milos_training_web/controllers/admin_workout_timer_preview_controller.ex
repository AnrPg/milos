defmodule MilosTrainingWeb.AdminWorkoutTimerPreviewController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.PreviewSectionTimer
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @segment_schema %Schema{
    type: :object,
    properties: %{
      label: %Schema{type: :string},
      label_key: %Schema{type: :string, nullable: true},
      label_params: %Schema{
        type: :object,
        additionalProperties: %Schema{oneOf: [%Schema{type: :integer}, %Schema{type: :string}]}
      },
      kind: %Schema{type: :string, enum: ~w(countdown countup manual no_timer interval_cycle)},
      phase: %Schema{type: :string, enum: ~w(work rest transition)},
      duration_seconds: %Schema{type: :integer, nullable: true},
      round: %Schema{type: :integer, nullable: true},
      total_rounds: %Schema{type: :integer, nullable: true}
    },
    required: [:label, :kind, :phase, :duration_seconds, :round, :total_rounds]
  }

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  operation(:create,
    summary: "Preview the timer sequence a draft section will run",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              section: %Schema{
                type: :object,
                description:
                  "Draft section: name, timer_config, exercises, section_metadata and rest_before_next_section_seconds.",
                additionalProperties: true
              }
            },
            required: [:section]
          }
        }
      }
    },
    responses: [
      ok:
        {"Timer sequence preview", "application/json",
         %Schema{
           type: :object,
           properties: %{
             segments: %Schema{type: :array, items: @segment_schema},
             total_seconds: %Schema{type: :integer},
             open_ended: %Schema{type: :boolean}
           },
           required: [:segments, :total_seconds, :open_ended]
         }},
      unprocessable_entity: {"Invalid timer configuration", "application/json", @error_schema},
      unauthorized: {"Unauthorized", "application/json", @error_schema},
      forbidden: {"Forbidden", "application/json", @error_schema}
    ]
  )

  def create(conn, _params) do
    section = conn.body_params[:section] || conn.body_params["section"]

    case PreviewSectionTimer.call(stringify_keys(section)) do
      {:ok, preview} ->
        json(conn, preview)

      {:error, {:invalid_timer_config, message}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{code: "invalid_timer_config", error: "timer_config #{message}"})
    end
  end

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
