defmodule MilosTrainingWeb.AdminWorkoutDslController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    GetWorkoutDslAuthoring,
    GetWorkoutDslManual,
    ParseWorkoutDsl,
    PublishWorkoutDsl
  }

  alias MilosTrainingWeb.Schemas.WorkoutDsl, as: WorkoutDslSchema
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @error_schema %Schema{
    type: :object,
    properties: %{
      code: %Schema{type: :string},
      error: %Schema{type: :string},
      diagnostics: %Schema{type: :array, items: WorkoutDslSchema.diagnostic_schema()}
    },
    required: [:code, :error]
  }

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
        json(
          conn,
          Map.update!(
            preview,
            :diagnostics,
            &Enum.map(&1, fn diagnostic -> json_diagnostic(diagnostic) end)
          )
        )

      {:error, diagnostics} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{diagnostics: Enum.map(diagnostics, &json_diagnostic/1)})
    end
  end

  operation(:show_authoring,
    summary: "Get retained or canonically generated Quick Text source",
    parameters: [@id_param],
    responses: [
      ok:
        {"Quick Text authoring state", "application/json",
         WorkoutDslSchema.authoring_response_schema()},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def show_authoring(conn, params) do
    id = params[:id] || params["id"]

    with {:ok, authoring} <- GetWorkoutDslAuthoring.call(conn.assigns.tenant_context, id) do
      json(conn, authoring)
    end
  end

  operation(:manual,
    summary: "Get the versioned coach manual, templates, and vocabulary",
    responses: [
      ok: {"Quick Text manual", "application/json", WorkoutDslSchema.manual_response_schema()}
    ]
  )

  def manual(conn, _params) do
    with {:ok, manual} <- GetWorkoutDslManual.call() do
      json(conn, manual)
    end
  end

  operation(:publish,
    summary: "Parse, preflight, and publish an exact Quick Text source revision",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: WorkoutDslSchema.publish_request_schema()}
      }
    },
    responses: [
      ok:
        {"Published canonical workout", "application/json",
         WorkoutDslSchema.publish_response_schema()},
      conflict:
        {"Revision conflict or warning acknowledgement required", "application/json",
         @error_schema},
      unprocessable_entity:
        {"DSL or canonical validation failed", "application/json",
         WorkoutDslSchema.diagnostic_response_schema()}
    ]
  )

  def publish(conn, params) do
    id = params[:id] || params["id"]

    case PublishWorkoutDsl.call(conn.assigns.tenant_context, id, conn.body_params) do
      {:ok, result} ->
        json(conn, json_publish_result(result))

      {:error, diagnostics} when is_list(diagnostics) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{diagnostics: Enum.map(diagnostics, &json_diagnostic/1)})

      error ->
        error
    end
  end

  defp json_diagnostic(diagnostic) do
    diagnostic
    |> Map.update!(:code, &Atom.to_string/1)
    |> Map.update!(:severity, &Atom.to_string/1)
    |> Map.update!(:params, &stringify_param_keys/1)
  end

  defp stringify_param_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp json_publish_result(result) do
    Map.update!(
      result,
      :diagnostics,
      &Enum.map(&1, fn diagnostic -> json_diagnostic(diagnostic) end)
    )
  end
end
