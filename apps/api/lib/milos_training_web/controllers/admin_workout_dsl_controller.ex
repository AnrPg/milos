defmodule MilosTrainingWeb.AdminWorkoutDslController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.ParseWorkoutDsl
  alias MilosTrainingWeb.Schemas.WorkoutDsl, as: WorkoutDslSchema
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  operation(:parse,
    summary: "Parse and canonically format Quick Text workout source",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: WorkoutDslSchema.parse_request_schema()}
      }
    },
    responses: [
      ok:
        {"Canonical workout preview", "application/json",
         WorkoutDslSchema.parse_response_schema()},
      unprocessable_entity:
        {"DSL diagnostics", "application/json", WorkoutDslSchema.diagnostic_response_schema()},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def parse(conn, _params) do
    source = conn.body_params[:source] || conn.body_params["source"]

    case ParseWorkoutDsl.call(source) do
      {:ok, preview} ->
        json(conn, preview)

      {:error, diagnostics} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{diagnostics: Enum.map(diagnostics, &json_diagnostic/1)})
    end
  end

  defp json_diagnostic(diagnostic) do
    diagnostic
    |> Map.update!(:code, &Atom.to_string/1)
    |> Map.update!(:params, &stringify_param_keys/1)
  end

  defp stringify_param_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
